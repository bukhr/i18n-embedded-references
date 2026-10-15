# frozen_string_literal: true

module I18n
  module EmbeddedReferences
    # Case transforms a reference may apply to the referenced text,
    # `${key|upcase}`, chained left to right: `${key|downcase|upcase_first}`.
    #
    # Interpolation placeholders (`%{name}`, `%<name>d`, `%%`) survive the
    # transform: the text around them is transformed and the placeholders are
    # kept verbatim, so interpolation still finds them afterwards. Transforms
    # that act on the first character do so once, on the whole string, so a
    # placeholder in the middle does not restart them.
    #
    # Only the names below are accepted. The backend raises on an unknown
    # name and the checker reports it, so a typo never silently leaks the
    # marker into the output.
    module Transforms
      module_function

      def upcase(string)
        each_text_run(string, &:upcase)
      end

      def downcase(string)
        each_text_run(string, &:downcase)
      end

      # Like String#capitalize: first character up, everything else down.
      def capitalize(string)
        upcase_first(downcase(string))
      end

      def upcase_first(string)
        string.empty? ? string : string[0].upcase + string[1..]
      end

      def downcase_first(string)
        string.empty? ? string : string[0].downcase + string[1..]
      end

      NAMES = %w[upcase downcase capitalize upcase_first downcase_first].freeze

      def known?(name)
        NAMES.include?(name)
      end

      def unknown(names)
        names.reject { |name| known?(name) }
      end

      # Applies the transforms in order. Names must be known (see `unknown`).
      def apply(names, string)
        names.reduce(string) { |text, name| public_send(name, text) }
      end

      # Rebuilds the string with the block applied to every run of text that
      # is not an interpolation placeholder.
      def each_text_run(string)
        result = +''
        last = 0
        string.scan(placeholder_pattern) do
          match = Regexp.last_match
          result << yield(string[last...match.begin(0)]) << match[0]
          last = match.end(0)
        end
        result << yield(string[last..])
      end

      # The placeholders I18n interpolates, as configured in the running app
      # (`I18n.config.interpolation_patterns`, i18n >= 1.9).
      def placeholder_pattern
        patterns = I18n.config.interpolation_patterns
        (@placeholder_patterns ||= {})[patterns] ||= Regexp.union(patterns)
      end
    end
  end
end
