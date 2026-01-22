# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.1] - 2026-01-22

### Added
- **`bundle age_gate_cleanup` command**: Automatically removes exceptions that are no longer needed

## [0.4.0] - 2026-01-22

### Added
- **Parallel gem checking**: Concurrent HTTP requests for faster age verification
- New configuration option: `max_workers` (range: 1-16, default: 8)
- Thread-safe data structures with Mutex guards for concurrent access
- Graceful fallback to sequential processing if parallelisation fails

### Changed
- Refactored `Command#execute` for parallelisation support
- Added `check_gems_parallel()` and `check_gems_sequential()` methods
- HTTP I/O operations now execute concurrently without blocking

### Backwards Compatibility
- Existing configs work unchanged (defaults to 8 workers)
- Set `max_workers: 1` for sequential processing (debugging or CI constraints)

## [0.3.0] - 2026-01-22

### Added
- **Multi-source support**: Configure different age requirements per gem source
  - Public RubyGems (strict) vs private gems (permissive)
  - Per-source API endpoint configuration
  - GitHub Packages, Artifactory, and custom registry support
- **Authentication support**: Bearer tokens for private gem servers
  - Environment variable substitution (e.g., `${GITHUB_TOKEN}`)
- **Source detection**: Automatically determines gem sources from Gemfile.lock
- **Per-source minimum age**: Different requirements for public vs internal gems
- **CLI override**: Command-line days argument overrides all source configurations

### Changed
- Violation output now includes source name and required age
- Configuration structure expanded to support multiple sources
- Default configuration maintains backwards compatibility (RubyGems only)

## [0.2.0] - 2026-01-22

### Added
- Configuration file support (`.bundler-age-gate.yml`)
- Exception handling mechanism with approval workflow
- Audit logging for compliance (JSON format)
- CI/CD integration examples:
  - GitHub Actions with PR comments
  - GitLab CI
  - CircleCI
  - Pre-commit hooks (shell and framework)
- Configuration examples and templates
- Comprehensive README documentation for enterprise deployment

### Changed
- Command now reads from config file for default minimum age
- Exit messages now include helpful hints for exceptions

### Fixed
- Plugin compatibility with Bundler 4.x

## [0.1.0] - 2026-01-22

### Added
- Initial release
- `bundle age_check [DAYS]` command to verify gem ages
- RubyGems API integration for release date checking
- In-memory caching to avoid duplicate API calls
- Progress indicator with dot-per-gem output
- Clear violation reporting with release dates
- Graceful error handling for API failures
- Exit code 0 for pass, 1 for violations

[0.1.0]: https://github.com/NikoRoberts/bundler-age_gate/releases/tag/v0.1.0
