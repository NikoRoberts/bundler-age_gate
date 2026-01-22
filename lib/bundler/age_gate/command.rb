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
      def initialize(days = nil)
        @config = Config.new
        @cli_override_days = days&.to_i
        @cache = {}
        @violations = []
        @excepted_violations = []
        @audit_logger = AuditLogger.new(@config.audit_log_path)
        @checked_gems_count = 0
        @source_map = {}  # gem_name => source_url

        # Thread-safety primitives for parallel processing
        @cache_mutex = Mutex.new          # Protect @cache hash
        @violations_mutex = Mutex.new     # Protect @violations arrays
        @progress_mutex = Mutex.new       # Protect stdout
        @checked_count_mutex = Mutex.new  # Protect counter
      end

      def clean_exceptions
        config_path = File.join(Dir.pwd, ".bundler-age-gate.yml")

        unless File.exist?(config_path)
          puts "ℹ️  No .bundler-age-gate.yml found in current directory"
          exit 0
        end

        lockfile_path = File.join(Dir.pwd, "Gemfile.lock")
        unless File.exist?(lockfile_path)
          puts "❌ Gemfile.lock not found in current directory"
          exit 1
        end

        # Load config
        config_data = YAML.safe_load_file(config_path, permitted_classes: [Date, Time]) || {}
        exceptions = config_data["exceptions"] || []

        if exceptions.empty?
          puts "ℹ️  No exceptions found in .bundler-age-gate.yml"
          exit 0
        end

        puts "🔍 Checking #{exceptions.size} exception(s) for cleanup..."
        puts ""

        # Parse lockfile
        lockfile = Bundler::LockfileParser.new(Bundler.read_file(lockfile_path))
        build_source_map(lockfile)

        # Check each exception
        removable_exceptions = []
        kept_exceptions = []

        exceptions.each do |exception|
          gem_name = exception["gem"]
          gem_version = exception["version"]

          # Find gem spec
          gem_spec = lockfile.specs.find do |spec|
            spec.name == gem_name && (gem_version.nil? || spec.version.to_s == gem_version)
          end

          unless gem_spec
            puts "⚠️  #{gem_name}#{gem_version ? " (#{gem_version})" : ""} - Not in Gemfile.lock (keeping exception)"
            kept_exceptions << exception
            next
          end

          # Check if exception is still needed
          gem_source_url = @source_map[gem_name] || "https://rubygems.org"
          source_config = @config.source_for_url(gem_source_url)
          min_age_days = @cli_override_days || source_config.minimum_age_days
          cutoff_date = Time.now - (min_age_days * 24 * 60 * 60)

          release_date = fetch_gem_release_date(gem_name, gem_spec.version.to_s, source_config)

          if release_date.nil?
            puts "⚠️  #{gem_name} (#{gem_spec.version}) - Could not determine release date (keeping exception)"
            kept_exceptions << exception
            next
          end

          age_days = ((Time.now - release_date) / (24 * 60 * 60)).round

          if release_date <= cutoff_date
            # Gem is now old enough - exception can be removed
            puts "✅ #{gem_name} (#{gem_spec.version}) - Released #{age_days} days ago (#{min_age_days} days required) - Removing"
            removable_exceptions << exception
          else
            # Still too new - keep exception
            puts "⏳ #{gem_name} (#{gem_spec.version}) - Released #{age_days} days ago (#{min_age_days} days required) - Keeping"
            kept_exceptions << exception
          end
        end

        puts ""

        if removable_exceptions.empty?
          puts "ℹ️  No exceptions can be removed at this time"
          exit 0
        end

        # Update config file
        config_data["exceptions"] = kept_exceptions
        File.write(config_path, YAML.dump(config_data))

        puts "✅ Removed #{removable_exceptions.size} exception(s) from .bundler-age-gate.yml"
        puts "📝 #{kept_exceptions.size} exception(s) remaining"
        exit 0
      end

      def execute
        lockfile_path = File.join(Dir.pwd, "Gemfile.lock")

        unless File.exist?(lockfile_path)
          puts "❌ Gemfile.lock not found in current directory"
          exit 1
        end

        lockfile = Bundler::LockfileParser.new(Bundler.read_file(lockfile_path))
        gems = lockfile.specs

        # Build source map from lockfile
        build_source_map(lockfile)

        # Display configuration
        if @cli_override_days
          puts "🔍 Checking gem ages (CLI override: #{@cli_override_days} days for all sources)..."
          puts "📅 Cutoff date: #{Time.now - (@cli_override_days * 24 * 60 * 60)}"
        else
          puts "🔍 Checking gem ages (per-source configuration)..."
          @config.sources.each do |source|
            puts "  📦 #{source.name}: #{source.minimum_age_days} days"
          end
        end
        puts ""

        puts "Checking #{gems.size} gems..."
        print "Progress: "

        # Determine worker count
        max_workers = @config.max_workers || 8
        worker_count = [[max_workers, gems.size].min, 1].max

        # Parallel or sequential
        if worker_count > 1
          check_gems_parallel(gems, worker_count)
        else
          check_gems_sequential(gems)
        end

        puts "\n\n"
        display_results
      end

      private

      def check_gems_parallel(gems, worker_count)
        work_queue = Queue.new
        gems.each { |spec| work_queue << spec }

        # Create worker threads
        workers = Array.new(worker_count) do
          Thread.new do
            loop do
              spec = work_queue.pop(true) rescue break  # Non-blocking pop
              check_gem_thread_safe(spec)
            end
          end
        end

        # Wait for all workers to complete
        workers.each(&:join)
      rescue StandardError => e
        warn "\n⚠️  Parallel processing failed: #{e.message}"
        warn "Falling back to sequential processing..."
        check_gems_sequential(gems)
      end

      def check_gems_sequential(gems)
        gems.each do |spec|
          check_gem(spec)
          print "."
        end
      end

      def check_gem_thread_safe(spec)
        gem_name = spec.name
        gem_version = spec.version.to_s
        cache_key = "#{gem_name}@#{gem_version}"

        # Check cache with lock
        cached = @cache_mutex.synchronize { @cache[cache_key] }
        return if cached

        # Increment counter with lock
        @checked_count_mutex.synchronize { @checked_gems_count += 1 }

        # Read-only operations (no locks needed)
        gem_source_url = @source_map[gem_name] || "https://rubygems.org"
        source_config = @config.source_for_url(gem_source_url)
        min_age_days = @cli_override_days || source_config.minimum_age_days
        cutoff_date = Time.now - (min_age_days * 24 * 60 * 60)

        # HTTP I/O happens here (NO LOCK - this gets parallelized!)
        release_date = fetch_gem_release_date(gem_name, gem_version, source_config)

        if release_date.nil?
          @cache_mutex.synchronize { @cache[cache_key] = :unknown }
          print_progress_dot
          return
        end

        @cache_mutex.synchronize { @cache[cache_key] = release_date }

        # Check violation
        if release_date > cutoff_date
          age_days = ((Time.now - release_date) / (24 * 60 * 60)).round
          violation = {
            name: gem_name,
            version: gem_version,
            release_date: release_date,
            age_days: age_days,
            source: source_config.name,
            required_age: min_age_days
          }

          if @config.gem_excepted?(gem_name, gem_version)
            violation[:excepted] = true
            violation[:exception_reason] = @config.exception_reason(gem_name, gem_version)
            @violations_mutex.synchronize { @excepted_violations << violation }
          else
            @violations_mutex.synchronize { @violations << violation }
          end
        end

        print_progress_dot
      rescue StandardError => e
        @cache_mutex.synchronize { @cache[cache_key] = :error }
        print_progress_dot
      end

      def print_progress_dot
        @progress_mutex.synchronize { print "." }
      end

      def build_source_map(lockfile)
        # Parse REMOTE sections from lockfile to map gems to sources
        lockfile_content = File.read(File.join(Dir.pwd, "Gemfile.lock"))
        current_source = nil

        lockfile_content.each_line do |line|
          if line.match(/^\s*remote: (.+)$/)
            current_source = line.match(/^\s*remote: (.+)$/)[1].strip
          elsif line.match(/^\s{4}(\S+)/) && current_source
            gem_name_with_version = line.strip
            gem_name = gem_name_with_version.split(/\s+/).first
            @source_map[gem_name] = current_source
          end
        end
      end

      def check_gem(spec)
        gem_name = spec.name
        gem_version = spec.version.to_s

        # Skip if already checked
        cache_key = "#{gem_name}@#{gem_version}"
        return if @cache.key?(cache_key)

        @checked_gems_count += 1

        # Determine source and minimum age for this gem
        gem_source_url = @source_map[gem_name] || "https://rubygems.org"
        source_config = @config.source_for_url(gem_source_url)
        min_age_days = @cli_override_days || source_config.minimum_age_days
        cutoff_date = Time.now - (min_age_days * 24 * 60 * 60)

        release_date = fetch_gem_release_date(gem_name, gem_version, source_config)

        if release_date.nil?
          # Couldn't determine date, skip silently
          @cache[cache_key] = :unknown
          return
        end

        @cache[cache_key] = release_date

        if release_date > cutoff_date
          age_days = ((Time.now - release_date) / (24 * 60 * 60)).round
          violation = {
            name: gem_name,
            version: gem_version,
            release_date: release_date,
            age_days: age_days,
            source: source_config.name,
            required_age: min_age_days
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

      def fetch_gem_release_date(gem_name, gem_version, source_config)
        uri = URI(format(source_config.api_endpoint, gem_name))

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 10) do |http|
          request = Net::HTTP::Get.new(uri.path)

          # Add authentication header if configured
          if source_config.auth_token
            request["Authorization"] = "Bearer #{source_config.auth_token}"
          end

          http.request(request)
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
            puts "  ⚠️  #{violation[:name]} (#{violation[:version]}) [#{violation[:source]}]"
            puts "     Released: #{violation[:release_date].strftime('%Y-%m-%d')} (#{violation[:age_days]} days ago, requires #{violation[:required_age]} days)"
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
          puts "✅ All gems meet their source-specific age requirements"
          puts "🎉 Safe to proceed!"
          exit 0
        else
          puts "⚠️  Found #{@violations.size} gem(s) that don't meet age requirements:\n\n"

          @violations.sort_by { |v| v[:age_days] }.each do |violation|
            puts "  ❌ #{violation[:name]} (#{violation[:version]}) [#{violation[:source]}]"
            puts "     Released: #{violation[:release_date].strftime('%Y-%m-%d')} (#{violation[:age_days]} days ago, requires #{violation[:required_age]} days)"
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
