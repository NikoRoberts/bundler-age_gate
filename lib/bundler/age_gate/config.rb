# frozen_string_literal: true

require "yaml"

module Bundler
  module AgeGate
    class Config
      attr_reader :minimum_age_days, :exceptions, :audit_log_path

      DEFAULT_CONFIG = {
        "minimum_age_days" => 7,
        "exceptions" => [],
        "audit_log_path" => ".bundler-age-gate.log"
      }.freeze

      def initialize(config_path = ".bundler-age-gate.yml")
        @config_path = config_path
        @config = load_config
        @minimum_age_days = @config["minimum_age_days"]
        @exceptions = @config["exceptions"] || []
        @audit_log_path = @config["audit_log_path"]
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

      def load_config
        if File.exist?(@config_path)
          YAML.safe_load_file(@config_path, permitted_classes: [Date, Time])
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
    end
  end
end
