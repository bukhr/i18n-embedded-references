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
    # honoured for the referenced key as well as for the referencing one. The
    # requested locale is taken from the `fallback_original_locale` option
    # that `I18n::Backend::Fallbacks` passes down (i18n >= 1.9), so it works
    # whether Fallbacks sits on this backend or on a Chain above it.
    # Resolution happens before interpolation and pluralization, so a
    # referenced value may itself contain `%{}` placeholders.
    #
    # A missing referenced key makes a string translation missing (the
    # MissingTranslation names the absent key). Inside hashes and arrays the
    # missing reference is handled per element by the standard exception
    # handler, so one broken value does not take the whole structure down.
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
        with_requested_locale(options[:fallback_original_locale] || locale) { super }
      end

      protected

      def lookup(locale, key, scope = [], options = EMPTY_HASH)
        result = super
        return result unless result.is_a?(String) || result.is_a?(Hash) || result.is_a?(Array)

        resolve_embedded(result, options, nested: false)
      end

      private

      # Records the locale of the outermost translate call so that nested
      # reference lookups use it instead of whatever fallback locale the
      # referencing translation was found in. Only the call that set the
      # locale clears it: nested calls re-enter with the same locale and must
      # not wipe it before the remaining references are resolved.
      def with_requested_locale(locale)
        owner = Thread.current[REQUESTED_LOCALE_KEY].nil?
        Thread.current[REQUESTED_LOCALE_KEY] = locale if owner
        yield
      ensure
        Thread.current[REQUESTED_LOCALE_KEY] = nil if owner
      end

      def requested_locale
        Thread.current[REQUESTED_LOCALE_KEY] || I18n.locale
      end

      # `nested` is true for values found inside a hash or array.
      def resolve_embedded(subject, options, nested:)
        case subject
        when Hash
          subject.each_with_object({}) { |(k, v), h| h[k] = resolve_embedded(v, options, nested: true) }
        when Array
          subject.map { |v| resolve_embedded(v, options, nested: true) }
        when String
          resolve_string(subject, options, nested: nested)
        else
          subject
        end
      end

      def resolve_string(string, options, nested:)
        return string unless string.match?(TOKENIZER)

        tokens = string.split(TOKENIZER).reject(&:empty?)
        resolved = tokens.map { |token| resolve_token(token, options, nested: nested) }

        # A translation consisting of a single reference keeps the referenced
        # value as-is, so `${some.hash}` and `${some.array}` return structures.
        return resolved.first if resolved.size == 1 && !resolved.first.is_a?(String)

        resolved.join
      end

      def resolve_token(token, options, nested:)
        match = token.match(REFERENCE)
        return token unless match
        return token[1..] if match[1] # `$${key}` escapes to the literal `${key}`

        resolve_reference(match[2], options, nested: nested)
      end

      def resolve_reference(key, options, nested:)
        locale = requested_locale
        stack = (Thread.current[RESOLUTION_STACK_KEY] ||= [])
        entry = "#{locale}.#{key}"
        raise CircularReferenceError, stack + [entry] if stack.include?(entry)

        stack.push(entry)
        forwarded = options.reject { |k, _| NOT_FORWARDED_OPTIONS.include?(k) }
        # For a string translation, `throw: true` hands the MissingTranslation
        # of the referenced key to the outermost translate call, which applies
        # the caller's raise/throw/exception handler. Inside a structure the
        # element is resolved on its own so the rest of the hash or array
        # survives a broken reference.
        I18n.translate(key, **forwarded, locale: locale, throw: !nested)
      ensure
        stack.pop
        Thread.current[RESOLUTION_STACK_KEY] = nil if stack.empty?
      end
    end
  end
end
