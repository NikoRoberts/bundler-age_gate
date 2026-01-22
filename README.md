# Bundler::AgeGate

A Bundler plugin that enforces minimum gem age requirements by checking your `Gemfile.lock` against the RubyGems API.

## Why?

Freshly released gems may contain bugs or security vulnerabilities that haven't been discovered yet. This plugin helps you implement a "waiting period" policy before adopting new gem versions in production environments.

## Installation

Install the plugin:

```bash
bundle plugin install bundler-age_gate
```

Or add it to your project's plugin list:

```bash
bundle plugin install bundler-age_gate --local_git=/path/to/bundler-age_gate
```

## Usage

Check that all gems in your `Gemfile.lock` are at least 7 days old:

```bash
bundle age_check
```

Specify a custom minimum age (in days):

```bash
bundle age_check 14
```

Check for 30-day minimum:

```bash
bundle age_check 30
```

## How It Works

1. Parses your `Gemfile.lock` using Bundler's built-in parser
2. Queries the RubyGems API for each gem's release date
3. Compares the release date against your specified minimum age
4. Reports any violations and exits with status code 1 if violations are found

## Features

- **Efficient API usage**: Caches API responses to avoid duplicate requests
- **Progress indicator**: Prints a dot for each gem checked
- **Clear output**: Shows violating gems with release dates and age
- **Graceful error handling**: Skips gems that can't be checked (API errors, network issues)
- **CI-friendly**: Returns appropriate exit codes (0 for pass, 1 for fail)

## Example Output

```
🔍 Checking gem ages (minimum: 7 days)...
📅 Cutoff date: 2026-01-15

Checking 143 gems...
Progress: ...............................................

⚠️  Found 2 gem(s) younger than 7 days:

  ❌ rails (7.1.3)
     Released: 2026-01-20 (2 days ago)

  ❌ activerecord (7.1.3)
     Released: 2026-01-20 (2 days ago)

⛔ Age gate check FAILED
```

## Use Cases

- **Production deployments**: Ensure stability by waiting for community feedback
- **Security compliance**: Enforce policies requiring "battle-tested" versions
- **CI pipelines**: Add as a check in your continuous integration workflow
- **Risk management**: Reduce exposure to zero-day vulnerabilities in new releases

## Integrating with CI

Add to your CI pipeline (e.g., GitHub Actions):

```yaml
- name: Check gem ages
  run: bundle age_check 14
```

This will fail the build if any gem is younger than 14 days.

## Development

After checking out the repo:

```bash
bundle install
```

To test locally:

```bash
bundle exec rake
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/NikoRoberts/bundler-age_gate.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
