# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-04-07

### Added
- Initial release: library loading, version string, error handling (`C2pa.version`)
- Platform detection for aarch64-apple-darwin, x86_64-apple-darwin, x86_64-unknown-linux-gnu
- Full FFI binding stubs for Reader, Builder, and Signer (implementations in upcoming milestones)
- `C2PA_LIBRARY_PATH` env var override for custom library paths
- RuboCop + RSpec test infrastructure
- GC safety helpers (`with_gc_stress`, `after(:each) { GC.compact }`)
