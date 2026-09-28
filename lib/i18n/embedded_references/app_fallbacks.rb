# frozen_string_literal: true

module I18n
  module EmbeddedReferences
    # Reads the fallback configuration of the running app, so the checker
    # resolves references the same way I18n does at runtime without having to
    # repeat `config.i18n.fallbacks` as command line flags.
    module AppFallbacks
      module_function

      # Returns `{ enabled: true, chains: { locale => [chain] }, default_fallbacks: [...] }`
      # built from `I18n.fallbacks`. Each chain is the full runtime chain of the
      # locale. Defaults are only read when the fallbacks object exposes them (a
      # custom object may only implement `#[]`). When the backend does not use
      # fallbacks, returns `{ enabled: false, chains: {}, default_fallbacks: [] }`:
      # at runtime there is no fallback at all, not even the regional parent.
      def from_i18n
        return { enabled: false, chains: {}, default_fallbacks: [] } unless fallbacks_enabled?

        fallbacks = I18n.fallbacks
        chains = Array(I18n.available_locales).to_h do |locale|
          [locale.to_s, Array(fallbacks[locale]).map(&:to_s)]
        end
        defaults = fallbacks.respond_to?(:defaults) ? Array(fallbacks.defaults).map(&:to_s) : []
        { enabled: true, chains: chains, default_fallbacks: defaults }
      end

      # Fallbacks only apply at runtime when the backend class includes
      # I18n::Backend::Fallbacks (Rails does it with `config.i18n.fallbacks`).
      def fallbacks_enabled?
        defined?(I18n::Backend::Fallbacks) &&
          I18n.respond_to?(:fallbacks) &&
          I18n.backend.class.include?(I18n::Backend::Fallbacks)
      end

      def describe(app)
        unless app[:enabled]
          return 'App backend does not use I18n::Backend::Fallbacks ' \
                 "(RAILS_ENV=#{environment}): checking without fallbacks"
        end

        defaults = app[:default_fallbacks].empty? ? 'none' : app[:default_fallbacks].join(', ')
        "Using fallbacks from I18n.fallbacks (#{app[:chains].size} locales, defaults: #{defaults})"
      end

      def environment
        return Rails.env if defined?(Rails) && Rails.respond_to?(:env)

        ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'unknown'
      end
    end
  end
end
