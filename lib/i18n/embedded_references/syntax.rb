# frozen_string_literal: true

module I18n
  module EmbeddedReferences
    # The `${key}` grammar, shared by the backend and the checker so both
    # agree on what a reference is.
    #
    # - `${some.key}` is a reference to `some.key`, taken verbatim (no strip)
    # - `$${some.key}` is the literal text `${some.key}`
    # - `${}` is not a reference
    #
    # A string that is exactly one reference (no surrounding text, not even
    # whitespace) stands for the referenced value itself, which may be a hash
    # or an array.
    module Syntax
      Reference = Struct.new(:key)

      TOKENIZER = /(\$\$\{[^}]+\}|\$\{[^}]+\})/.freeze
      TOKEN = /\A(\$)?\$\{([^}]+)\}\z/.freeze

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

          Reference.new(match[2])
        end
      end

      def single_reference?(tokens)
        tokens.size == 1 && tokens.first.is_a?(Reference)
      end
    end
  end
end
