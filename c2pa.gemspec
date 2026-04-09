# frozen_string_literal: true

require_relative 'lib/c2pa/version'

Gem::Specification.new do |spec|
  spec.name    = 'c2pa'
  spec.version = C2pa::VERSION
  spec.authors = ['Abhishek Kumar Singh']
  spec.email   = ['abhissi@adobe.com']

  spec.summary     = 'Ruby bindings for the C2PA reference SDK (c2pa-rs)'
  spec.description = <<~DESC
    Official Ruby bindings for the C2PA (Coalition for Content Provenance and Authenticity)
    reference SDK. Provides full support for reading and writing Content Credentials,
    including the proxy-based deferred signing workflow for cloud media pipelines.
    Ships with precompiled native binaries — no Rust toolchain required.
  DESC
  spec.homepage = 'https://github.com/contentauth/c2pa-ruby'
  spec.licenses = ['MIT', 'Apache-2.0']

  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => 'https://github.com/contentauth/c2pa-ruby',
    'bug_tracker_uri' => 'https://github.com/contentauth/c2pa-ruby/issues',
    'changelog_uri' => 'https://github.com/contentauth/c2pa-ruby/blob/main/CHANGELOG.md',
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir[
    'lib/**/*.rb',
    'libs/**/*.dylib',
    'libs/**/*.so',
    'LICENSE-MIT',
    'LICENSE-APACHE',
    'README.md',
    'CHANGELOG.md'
  ]

  spec.require_paths = ['lib']

  spec.add_dependency 'ffi', '~> 1.15'
end
