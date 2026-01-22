# frozen_string_literal: true

require_relative "lib/bundler/age_gate/command"

Bundler::Plugin::API.command("age_check") do |args|
  days = args.first || "7"

  unless days.match?(/^\d+$/)
    puts "❌ Invalid argument: '#{days}' is not a valid number of days"
    puts "Usage: bundle age_check [DAYS]"
    exit 1
  end

  Bundler::AgeGate::Command.new(days).execute
end
