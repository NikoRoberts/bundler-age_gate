# frozen_string_literal: true

require_relative "lib/bundler/age_gate/command"

class AgeCheck < Bundler::Plugin::API
  command "age_check"

  def exec(_command, args)
    days = args.first || "7"

    unless days.match?(/^\d+$/)
      puts "❌ Invalid argument: '#{days}' is not a valid number of days"
      puts "Usage: bundle age_check [DAYS]"
      exit 1
    end

    Bundler::AgeGate::Command.new(days).execute
  end
end
