# frozen_string_literal: true

require "json"
require "time"

module Bundler
  module AgeGate
    class AuditLogger
      def initialize(log_path)
        @log_path = log_path
      end

      def log_check(result:, violations:, exceptions_used:, checked_gems_count:)
        entry = {
          timestamp: Time.now.iso8601,
          result: result, # "pass" or "fail"
          violations_count: violations.size,
          checked_gems_count: checked_gems_count,
          exceptions_used: exceptions_used,
          violations: violations.map do |v|
            {
              gem: v[:name],
              version: v[:version],
              release_date: v[:release_date].iso8601,
              age_days: v[:age_days],
              excepted: v[:excepted] || false,
              exception_reason: v[:exception_reason]
            }
          end
        }

        append_log(entry)
      end

      private

      def append_log(entry)
        File.open(@log_path, "a") do |f|
          f.puts(JSON.generate(entry))
        end
      rescue StandardError => e
        # Silently fail if logging doesn't work - don't block the main flow
        warn "⚠️  Failed to write audit log: #{e.message}"
      end
    end
  end
end
