# frozen_string_literal: true

require "yaml"

module Bundler
  module AgeGate
    class Config
      attr_reader :minimum_age_days, :exceptions, :audit_log_path, :sources, :max_workers

      DEFAULT_RUBYGEMS_SOURCE = {
        "name" => "rubygems",
        "url" => "https://rubygems.org",
        "api_endpoint" => "https://rubygems.org/api/v1/versions/%s.json",
        "minimum_age_days" => nil # Uses global default
      }.freeze

      DEFAULT_CONFIG = {
        "minimum_age_days" => 7,
        "exceptions" => [],
        "audit_log_path" => ".bundler-age-gate.log",
        "sources" => [DEFAULT_RUBYGEMS_SOURCE],
        "max_workers" => 8
      }.freeze

      def initialize(config_path = ".bundler-age-gate.yml")
        @config_path = config_path
        @config = load_config
        @minimum_age_days = @config["minimum_age_days"]
        @exceptions = @config["exceptions"] || []
        @audit_log_path = @config["audit_log_path"]
        @sources = (@config["sources"] || [DEFAULT_RUBYGEMS_SOURCE]).map { |s| SourceConfig.new(s, @minimum_age_days) }
        @max_workers = parse_max_workers(@config["max_workers"])
      end

      def source_for_url(source_url)
        # Normalise URLs for comparison
        normalised_url = normalise_source_url(source_url)

        @sources.find do |source|
          normalise_source_url(source.url) == normalised_url
        end || @sources.first # Default to first source (usually rubygems)
      end

      def gem_excepted?(gem_name, gem_version)
        @exceptions.any? do |exception|
          matches_gem?(exception, gem_name, gem_version) && !expired?(exception)
        end
      end

      def exception_reason(gem_name, gem_version)
        exception = @exceptions.find do |ex|
          matches_gem?(ex, gem_name, gem_version) && !expired?(ex)
        end
        exception&.dig("reason")
      end

      private

      def parse_max_workers(value)
        return 8 unless value

        workers = value.to_i
        if workers < 1
          warn "⚠️  Invalid max_workers: #{value}. Using default: 8"
          8
        elsif workers > 16
          warn "⚠️  max_workers > 16. Using maximum: 16"
          16
        else
          workers
        end
      end

      def load_config
        if File.exist?(@config_path)
          user_config = YAML.safe_load_file(@config_path, permitted_classes: [Date, Time])
          DEFAULT_CONFIG.merge(user_config || {})
        else
          DEFAULT_CONFIG
        end
      rescue StandardError => e
        warn "⚠️  Failed to load config from #{@config_path}: #{e.message}"
        warn "Using default configuration"
        DEFAULT_CONFIG
      end

      def matches_gem?(exception, gem_name, gem_version)
        exception["gem"] == gem_name &&
          (exception["version"].nil? || exception["version"] == gem_version)
      end

      def expired?(exception)
        return false unless exception["expires"]

        expiry_date = parse_date(exception["expires"])
        expiry_date && Time.now > expiry_date
      end

      def parse_date(date_string)
        Time.parse(date_string.to_s)
      rescue ArgumentError
        nil
      end

      def normalise_source_url(url)
        # Remove trailing slashes and convert to lowercase for comparison
        url.to_s.downcase.chomp("/")
      end
    end

    # Represents a gem source configuration
    class SourceConfig
      attr_reader :name, :url, :api_endpoint, :minimum_age_days, :auth_token

      def initialize(config, global_minimum_age_days)
        @name = config["name"] || "unknown"
        @url = config["url"]
        @api_endpoint = config["api_endpoint"]
        @minimum_age_days = config["minimum_age_days"] || global_minimum_age_days
        @auth_token = resolve_auth_token(config["auth_token"])
      end

      private

      def resolve_auth_token(token_config)
        return nil unless token_config

        # Support environment variable substitution: ${VAR_NAME}
        if token_config.match?(/\$\{(.+)\}/)
          var_name = token_config.match(/\$\{(.+)\}/)[1]
          ENV[var_name]
        else
          token_config
        end
      end
    end
  end
end
