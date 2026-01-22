require_relative 'lib/bundler/age_gate/command'
Dir.chdir('/Users/niko/work/dev/tmp/test-age-gate')
Bundler::AgeGate::Command.new.execute
