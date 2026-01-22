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

## Configuration

Create a `.bundler-age-gate.yml` file in your project root to customise behaviour:

```yaml
# Minimum age in days (default: 7)
minimum_age_days: 7

# Audit log path (default: .bundler-age-gate.log)
audit_log_path: .bundler-age-gate.log

# Approved exceptions
exceptions:
  - gem: rails
    version: 7.1.3.1
    reason: "Critical security patch for CVE-2024-12345"
    approved_by: security-team
    expires: 2026-02-15
```

### Exception Workflow

1. Developer encounters age gate violation
2. Request exception approval (security team, staff engineer, etc.)
3. Add approved exception to `.bundler-age-gate.yml`
4. Include reason, approver, and expiry date
5. Commit configuration with approval documented

**Exception fields:**
- `gem` (required): Gem name
- `version` (optional): Specific version, omit for all versions
- `reason` (required): Explanation for exception
- `approved_by` (required): Who approved this
- `expires` (optional): Expiry date (YYYY-MM-DD)

### Audit Logging

All checks are logged to `.bundler-age-gate.log` in JSON format:

```json
{
  "timestamp": "2026-01-22T13:45:00Z",
  "result": "pass",
  "violations_count": 0,
  "checked_gems_count": 80,
  "exceptions_used": 1,
  "violations": []
}
```

**Compliance benefits:**
- Track all security checks
- Audit exception usage
- Demonstrate policy compliance
- Investigate historical violations

### Multi-Source Support

Configure different age requirements for different gem sources (public vs private):

```yaml
minimum_age_days: 7  # Global default

sources:
  # Public RubyGems - strict
  - name: rubygems
    url: https://rubygems.org
    api_endpoint: https://rubygems.org/api/v1/versions/%s.json
    minimum_age_days: 7

  # Internal GitHub Packages - less strict
  - name: github-internal
    url: https://rubygems.pkg.github.com/your-org
    api_endpoint: https://rubygems.pkg.github.com/your-org/api/v1/versions/%s.json
    minimum_age_days: 3
    auth_token: ${GITHUB_TOKEN}  # Environment variable

  # Internal Artifactory - very permissive
  - name: artifactory
    url: https://artifactory.company.com/api/gems
    api_endpoint: https://artifactory.company.com/api/gems/api/v1/versions/%s.json
    minimum_age_days: 1
    auth_token: ${ARTIFACTORY_API_KEY}
```

**Benefits:**
- Stricter requirements for public gems (supply chain risk)
- Permissive for internal gems (trusted sources)
- Per-source API endpoints for private registries
- Authentication support via environment variables
- CLI override still applies globally: `bundle age_check 14` enforces 14 days for ALL sources

**How it works:**
1. Plugin reads `Gemfile.lock` to determine each gem's source
2. Applies per-source minimum age requirements
3. Queries appropriate API endpoint with authentication
4. Reports violations with source context

## How It Works

1. Parses your `Gemfile.lock` using Bundler's built-in parser
2. Queries the RubyGems API for each gem's release date
3. Compares the release date against your specified minimum age
4. Reports any violations and exits with status code 1 if violations are found

**Note:** Currently only supports rubygems.org. Private gem servers or GitHub packages are not yet supported. See [Roadmap](#roadmap) for planned features.

## Features

- **Efficient API usage**: Caches API responses to avoid duplicate requests
- **Progress indicator**: Prints a dot for each gem checked
- **Clear output**: Shows violating gems with release dates and age
- **Graceful error handling**: Skips gems that can't be checked (API errors, network issues)
- **CI-friendly**: Returns appropriate exit codes (0 for pass, 1 for fail)
- **Configuration file**: Customise settings via `.bundler-age-gate.yml`
- **Exception handling**: Approve specific gems with documented reasons
- **Audit logging**: Compliance-ready logs for all checks
- **Enterprise-ready**: Designed for organisation-wide rollout

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

## CI/CD Integration

### GitHub Actions

```yaml
# .github/workflows/gem-security-check.yml
- name: Install bundler-age_gate
  run: |
    gem install bundler-age_gate
    bundle plugin install bundler-age_gate

- name: Check gem ages
  run: bundle age_check 7
```

**Full example:** See [`examples/github-actions.yml`](examples/github-actions.yml) for complete workflow with PR comments and artefact upload.

### GitLab CI

```yaml
# .gitlab-ci.yml
gem-age-gate-check:
  script:
    - bundle plugin install bundler-age_gate
    - bundle age_check 7
```

**Full example:** See [`examples/gitlab-ci.yml`](examples/gitlab-ci.yml)

### CircleCI

```yaml
# .circleci/config.yml
- run:
    name: Check gem ages
    command: bundle age_check 7
```

**Full example:** See [`examples/circleci-config.yml`](examples/circleci-config.yml)

### Pre-commit Hooks

#### Shell Script

```bash
# .git/hooks/pre-commit
#!/bin/bash
if git diff --cached --name-only | grep -q "^Gemfile.lock$"; then
  bundle age_check 7
fi
```

**Installation:** See [`examples/pre-commit`](examples/pre-commit)

#### Pre-commit Framework

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: bundler-age-gate
        name: Check gem ages
        entry: bundle age_check 7
        language: system
        files: ^Gemfile\.lock$
```

**Full example:** See [`examples/.pre-commit-config.yaml`](examples/.pre-commit-config.yaml)

## Development

After checking out the repo:

```bash
bundle install
```

To test locally:

```bash
bundle exec rake
```

## Roadmap

Future enhancements planned:

- [x] **Private gem server support**: ✅ Implemented in v0.3.0
- [x] **Multi-source detection**: ✅ Implemented in v0.3.0
- [x] **Transitive dependency checking**: ✅ Already included (checks entire Gemfile.lock)
- [ ] **Webhook notifications**: Slack/Teams alerts for violations
- [ ] **Policy-as-code**: YAML policy files with team-specific rules
- [ ] **Exemption templates**: Pre-approved exception categories (security patches, internal gems)
- [ ] **Metrics dashboard**: Web dashboard for organisation-wide compliance
- [ ] **Dependency tree visualisation**: Show which gems introduced young dependencies

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/NikoRoberts/bundler-age_gate.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
