# frozen_string_literal: true

require "bundler"
require "net/http"
require "json"
require "time"
require_relative "config"
require_relative "audit_logger"

module Bundler
  module AgeGate
    class Command
      API_ENDPOINT = "https://rubygems.org/api/v1/versions/%s.json"

      def initialize(days = nil)
        @config = Config.new
        @min_age_days = days ? days.to_i : @config.minimum_age_days
        @cache = {}
        @violations = []
        @excepted_violations = []
        @cutoff_date = Time.now - (@min_age_days * 24 * 60 * 60)
        @audit_logger = AuditLogger.new(@config.audit_log_path)
        @checked_gems_count = 0
      end

      def execute
        puts "🔍 Checking gem ages (minimum: #{@min_age_days} days)..."
        puts "📅 Cutoff date: #{@cutoff_date.strftime('%Y-%m-%d')}"
        puts ""

        lockfile_path = File.join(Dir.pwd, "Gemfile.lock")

        unless File.exist?(lockfile_path)
          puts "❌ Gemfile.lock not found in current directory"
          exit 1
        end

        lockfile = Bundler::LockfileParser.new(Bundler.read_file(lockfile_path))
        gems = lockfile.specs

        puts "Checking #{gems.size} gems..."
        print "Progress: "

        gems.each do |spec|
          check_gem(spec)
          print "."
        end

        puts "\n\n"
        display_results
      end

      private

      def check_gem(spec)
        gem_name = spec.name
        gem_version = spec.version.to_s

        # Skip if already checked
        cache_key = "#{gem_name}@#{gem_version}"
        return if @cache.key?(cache_key)

        @checked_gems_count += 1
        release_date = fetch_gem_release_date(gem_name, gem_version)

        if release_date.nil?
          # Couldn't determine date, skip silently
          @cache[cache_key] = :unknown
          return
        end

        @cache[cache_key] = release_date

        if release_date > @cutoff_date
          age_days = ((Time.now - release_date) / (24 * 60 * 60)).round
          violation = {
            name: gem_name,
            version: gem_version,
            release_date: release_date,
            age_days: age_days
          }

          # Check if this gem has an exception
          if @config.gem_excepted?(gem_name, gem_version)
            violation[:excepted] = true
            violation[:exception_reason] = @config.exception_reason(gem_name, gem_version)
            @excepted_violations << violation
          else
            @violations << violation
          end
        end
      rescue StandardError => e
        # Silently handle errors for individual gems
        @cache[cache_key] = :error
      end

      def fetch_gem_release_date(gem_name, gem_version)
        uri = URI(format(API_ENDPOINT, gem_name))

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 10) do |http|
          http.get(uri.path)
        end

        unless response.is_a?(Net::HTTPSuccess)
          return nil
        end

        versions_data = JSON.parse(response.body)
        version_info = versions_data.find { |v| v["number"] == gem_version }

        return nil unless version_info && version_info["created_at"]

        Time.parse(version_info["created_at"])
      rescue StandardError
        nil
      end

      def display_results
        # Show excepted violations first (if any)
        unless @excepted_violations.empty?
          puts "ℹ️  #{@excepted_violations.size} gem(s) have approved exceptions:\n\n"

          @excepted_violations.sort_by { |v| v[:age_days] }.each do |violation|
            puts "  ⚠️  #{violation[:name]} (#{violation[:version]})"
            puts "     Released: #{violation[:release_date].strftime('%Y-%m-%d')} (#{violation[:age_days]} days ago)"
            puts "     Exception: #{violation[:exception_reason]}"
            puts ""
          end
        end

        # Log audit entry
        result = @violations.empty? ? "pass" : "fail"
        all_violations = @violations + @excepted_violations
        @audit_logger.log_check(
          result: result,
          violations: all_violations,
          exceptions_used: @excepted_violations.size,
          checked_gems_count: @checked_gems_count
        )

        # Display final result
        if @violations.empty?
          puts "✅ All gems meet the minimum age requirement (#{@min_age_days} days)"
          puts "🎉 Safe to proceed!"
          exit 0
        else
          puts "⚠️  Found #{@violations.size} gem(s) younger than #{@min_age_days} days:\n\n"

          @violations.sort_by { |v| v[:age_days] }.each do |violation|
            puts "  ❌ #{violation[:name]} (#{violation[:version]})"
            puts "     Released: #{violation[:release_date].strftime('%Y-%m-%d')} (#{violation[:age_days]} days ago)"
            puts ""
          end

          puts "⛔ Age gate check FAILED"
          puts "\n💡 To add an exception, create .bundler-age-gate.yml with approved exceptions"
          exit 1
        end
      end
    end
  end
end
