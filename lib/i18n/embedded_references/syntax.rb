# frozen_string_literal: true

module I18n
  module EmbeddedReferences
    # The `${key}` grammar, shared by the backend and the checker so both
    # agree on what a reference is.
    #
    # - `${some.key}` is a reference to `some.key`, taken verbatim (no strip)
    # - `${some.key|upcase}` applies a transform to the referenced text;
    #   `${some.key|downcase|upcase_first}` chains them left to right
    # - `$${some.key}` is the literal text `${some.key}`
    # - `${}` is not a reference
    #
    # Transform names are taken verbatim too and validated elsewhere (see
    # Transforms): the grammar only splits them off the key.
    #
    # A string that is exactly one reference (no surrounding text, not even
    # whitespace) stands for the referenced value itself, which may be a hash
    # or an array.
    module Syntax
      Reference = Struct.new(:key, :transforms) do
        def initialize(key, transforms = [])
          super
        end

        def transforms?
          !transforms.empty?
        end

        # The reference as written, for messages: `${key|upcase}`.
        def marker
          "${#{[key, *transforms].join(TRANSFORM_SEPARATOR)}}"
        end
      end

      TOKENIZER = /(\$\$\{[^}]+\}|\$\{[^}]+\})/.freeze
      TOKEN = /\A(\$)?\$\{([^}]+)\}\z/.freeze
      TRANSFORM_SEPARATOR = '|'

      module_function

      # Whether the string may contain references or escapes at all.
      def markers?(string)
        string.include?('${')
      end

      # Splits a string into literal Strings and References, in order.
      # Escapes come back as literal text.
      def tokenize(string)
        return [string] unless markers?(string)

        string.split(TOKENIZER).reject(&:empty?).map do |token|
          match = token.match(TOKEN)
          next token unless match
          next token[1..] if match[1] # `$${key}` escapes to the literal `${key}`

          key, *transforms = match[2].split(TRANSFORM_SEPARATOR, -1)
          Reference.new(key, transforms)
        end
      end

      def single_reference?(tokens)
        tokens.size == 1 && tokens.first.is_a?(Reference)
      end
    end
  end
end
