# frozen_string_literal: true

require 'test_helper'
require 'i18n/embedded_references/app_fallbacks'

class AppFallbacksTest < BackendTestCase
  def test_disabled_when_backend_does_not_use_fallbacks
    I18n.backend = Backend.new
    assert_equal({ enabled: false, chains: {}, default_fallbacks: [] },
                 I18n::EmbeddedReferences::AppFallbacks.from_i18n)
  end

  def test_reads_chains_and_defaults_from_i18n_fallbacks
    I18n.backend = FallbacksBackend.new
    I18n.available_locales = %i[es es-CL pt pt-BR]
    I18n.fallbacks = [:es]
    app = I18n::EmbeddedReferences::AppFallbacks.from_i18n

    assert app[:enabled]
    assert_equal %w[es], app[:default_fallbacks]
    assert_equal %w[pt-BR pt es], app[:chains]['pt-BR']
    assert_equal %w[es-CL es], app[:chains]['es-CL']
    assert_equal %w[es es-CL pt pt-BR], app[:chains].keys.sort
  end

  def test_detects_fallbacks_included_on_a_chain
    I18n.backend = FallbacksChain.new(Backend.new)
    I18n.available_locales = %i[en pt]
    I18n.fallbacks = [:en]
    assert_equal %w[pt en], I18n::EmbeddedReferences::AppFallbacks.from_i18n[:chains]['pt']
  end

  # Only implements `#[]`, like a hand-rolled `I18n.fallbacks` object.
  class CustomFallbacks
    def [](locale)
      locale.to_s == 'de-AT' ? %i[de-AT de-DE de] : [locale.to_sym]
    end
  end

  def test_custom_fallbacks_object_without_defaults
    I18n.backend = FallbacksBackend.new
    I18n.available_locales = %i[de de-AT]
    I18n.fallbacks = CustomFallbacks.new
    app = I18n::EmbeddedReferences::AppFallbacks.from_i18n

    assert_equal [], app[:default_fallbacks]
    assert_equal %w[de-AT de-DE de], app[:chains]['de-AT']
  end

  def test_describe
    app = { enabled: true, chains: { 'pt' => %w[pt es] }, default_fallbacks: %w[es] }
    assert_equal 'Using fallbacks from I18n.fallbacks (1 locales, defaults: es)',
                 I18n::EmbeddedReferences::AppFallbacks.describe(app)
  end

  def test_describe_disabled_names_the_environment
    app = { enabled: false, chains: {}, default_fallbacks: [] }
    previous = %w[RAILS_ENV RACK_ENV].to_h { |k| [k, ENV.fetch(k, nil)] }
    ENV['RAILS_ENV'] = 'test'
    ENV['RACK_ENV'] = nil
    assert_equal 'App backend does not use I18n::Backend::Fallbacks (RAILS_ENV=test): checking without fallbacks',
                 I18n::EmbeddedReferences::AppFallbacks.describe(app)
  ensure
    previous&.each { |k, v| ENV[k] = v }
  end
end
