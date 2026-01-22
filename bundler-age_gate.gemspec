# frozen_string_literal: true

require_relative "lib/bundler/age_gate/version"

Gem::Specification.new do |spec|
  spec.name = "bundler-age_gate"
  spec.version = Bundler::AgeGate::VERSION
  spec.authors = ["Niko Roberts"]
  spec.email = ["niko.roberts@airtasker.com"]

  spec.summary = "A Bundler plugin to enforce minimum gem age requirements"
  spec.description = "Checks your Gemfile.lock against the RubyGems API to ensure no gems are younger than a specified number of days"
  spec.homepage = "https://github.com/NikoRoberts/bundler-age_gate"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.glob("lib/**/*") + %w[
    plugins.rb
    bundler-age_gate.gemspec
    README.md
    LICENSE
    CHANGELOG.md
  ].select { |f| File.exist?(f) }

  spec.require_paths = ["lib"]

  spec.add_dependency "bundler", ">= 2.0"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
end
