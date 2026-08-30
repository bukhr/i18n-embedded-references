# frozen_string_literal: true

require 'i18n'

module I18n
  module Backend
    # Resolves `${some.key}` markers found inside translations by looking up
    # the referenced key and splicing its value in place. `$${some.key}`
    # produces the literal text `${some.key}`.
    #
    # Include it in any backend that implements `lookup`:
    #
    #   I18n::Backend::Simple.include(I18n::Backend::EmbeddedReferences)
    #
    # References are resolved through `I18n.translate`, with the locale that
    # was originally requested, so fallback chains and backend chains are
    # honoured for the referenced key as well as for the referencing one.
    # Resolution happens before interpolation and pluralization, so a
    # referenced value may itself contain `%{}` placeholders.
    module EmbeddedReferences
      class CircularReferenceError < I18n::ArgumentError
        def initialize(chain)
          super("circular embedded reference: #{chain.join(' -> ')}")
        end
      end

      TOKENIZER = /(\$\$\{[^}]+\}|\$\{[^}]+\})/.freeze
      REFERENCE = /\A(\$)?\$\{([^}]+)\}\z/.freeze

      REQUESTED_LOCALE_KEY = :i18n_embedded_references_requested_locale
      RESOLUTION_STACK_KEY = :i18n_embedded_references_stack

      # Options that only make sense for the referencing lookup and must not
      # leak into the nested translate call. Everything else (interpolation
      # values, `count`, `exception_handler`, ...) is forwarded so that a
      # referenced value is interpolated and pluralized like the caller asked.
      NOT_FORWARDED_OPTIONS = %i[
        scope default separator locale object format resolve cascade deep_interpolation
        fallback fallback_in_progress fallback_original_locale
      ].freeze

      def translate(locale, key, options = EMPTY_HASH)
        with_requested_locale(locale) { super }
      end

      protected

      def lookup(locale, key, scope = [], options = EMPTY_HASH)
        result = super
        return result unless result.is_a?(String) || result.is_a?(Hash) || result.is_a?(Array)

        resolve_embedded(result, options)
      end

      private

      # Records the locale of the outermost translate call so that nested
      # reference lookups use it instead of whatever fallback locale the
      # referencing translation was found in.
      def with_requested_locale(locale)
        return yield if Thread.current[REQUESTED_LOCALE_KEY]

        Thread.current[REQUESTED_LOCALE_KEY] = locale
        yield
      ensure
        Thread.current[REQUESTED_LOCALE_KEY] = nil if Thread.current[REQUESTED_LOCALE_KEY] == locale
      end

      def requested_locale
        Thread.current[REQUESTED_LOCALE_KEY] || I18n.locale
      end

      def resolve_embedded(subject, options)
        case subject
        when Hash
          subject.each_with_object({}) { |(k, v), h| h[k] = resolve_embedded(v, options) }
        when Array
          subject.map { |v| resolve_embedded(v, options) }
        when String
          resolve_string(subject, options)
        else
          subject
        end
      end

      def resolve_string(string, options)
        return string unless string.match?(TOKENIZER)

        resolved = string.split(TOKENIZER).reject(&:empty?).map { |token| resolve_token(token, options) }

        # A translation consisting of a single reference keeps the referenced
        # value as-is, so `${some.hash}` and `${some.array}` return structures.
        return resolved.first if resolved.size == 1 && !resolved.first.is_a?(String)

        resolved.join
      end

      def resolve_token(token, options)
        match = token.match(REFERENCE)
        return token unless match
        return token[1..] if match[1] # `$${key}` escapes to the literal `${key}`

        resolve_reference(match[2], options)
      end

      def resolve_reference(key, options)
        locale = requested_locale
        stack = (Thread.current[RESOLUTION_STACK_KEY] ||= [])
        entry = "#{locale}.#{key}"
        raise CircularReferenceError, stack + [entry] if stack.include?(entry)

        stack.push(entry)
        forwarded = options.reject { |k, _| NOT_FORWARDED_OPTIONS.include?(k) }
        # A missing referenced key makes the referencing translation missing;
        # `throw: true` hands the MissingTranslation to the outermost translate
        # call, which applies the caller's raise/throw/exception handler.
        I18n.translate(key, **forwarded, locale: locale, throw: true)
      ensure
        stack.pop
        Thread.current[RESOLUTION_STACK_KEY] = nil if stack.empty?
      end
    end
  end
end
