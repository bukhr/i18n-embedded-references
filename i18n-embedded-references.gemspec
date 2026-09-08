# frozen_string_literal: true

require_relative 'lib/i18n/embedded_references/version'

Gem::Specification.new do |spec|
  spec.name          = 'i18n-embedded-references'
  spec.version       = I18n::EmbeddedReferences::VERSION
  spec.authors       = ['Buk']
  spec.email         = ['opensource@buk.cl']

  spec.summary       = 'Reference other translations from inside a translation with ${key}.'
  spec.description   = <<~DESC
    An I18n backend extension that lets a translation embed other translations
    using the `${some.key}` marker. References are resolved lazily on lookup,
    recursively, with cycle detection and fallback-aware locale resolution.
    Works with strings, hashes and arrays. Successor of i18n-recursive-lookup.
  DESC
  spec.homepage      = 'https://github.com/bukhr/i18n-embedded-references'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 2.7'

  spec.metadata['homepage_uri']    = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri']   = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['lib/**/*.rb', 'exe/*', 'LICENSE', 'README.md', 'CHANGELOG.md']
  spec.bindir = 'exe'
  spec.executables = ['i18n-embedded-references']
  spec.require_paths = ['lib']

  spec.add_dependency 'i18n', '>= 1.8', '< 2'
end
