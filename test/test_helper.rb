# frozen_string_literal: true

require 'minitest/autorun'
require 'i18n/embedded_references'

class BackendTestCase < Minitest::Test
  class Backend < I18n::Backend::Simple
    include I18n::Backend::EmbeddedReferences
  end

  class FallbacksBackend < I18n::Backend::Simple
    include I18n::Backend::Fallbacks
    include I18n::Backend::EmbeddedReferences
  end

  # Rails includes Fallbacks into the class of the root backend, which in
  # apps using Chain is the Chain itself, above the Simple backend.
  class FallbacksChain < I18n::Backend::Chain
    include I18n::Backend::Fallbacks
  end

  def setup
    I18n.backend = Backend.new
    I18n.enforce_available_locales = false
    I18n.locale = :en
    I18n.default_locale = :en
  end

  def teardown
    I18n.backend = nil
    I18n.fallbacks = nil if I18n.respond_to?(:fallbacks=)
    I18n.locale = :en
  end

  def store(locale, data)
    I18n.backend.store_translations(locale, data)
  end
end
