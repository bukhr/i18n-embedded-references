# frozen_string_literal: true

require 'yaml'
require 'set'
require 'date'

module I18n
  module EmbeddedReferences
    # Static analysis of `${key}` references across locale YAML files.
    #
    # Loads the files without booting I18n or Rails, flattens them into
    # `{ locale => { "dotted.key" => value } }` and verifies every reference:
    #
    # - broken:  the target key does not exist in the locale or its fallbacks
    # - cycle:   following references leads back to the starting key
    # - scope:   a reference embedded in text points at a Hash/Array target
    #
    # Fallbacks default to the region-stripped parent (`es-CL` -> `es`), can be
    # extended per locale, and `default_fallbacks` are appended to every chain
    # (the equivalent of `I18n.fallbacks = [:es]`). `ignore_missing` takes key
    # globs for keys resolved elsewhere (another backend, a database, ...).
    class Checker
      Problem = Struct.new(:kind, :severity, :locale, :key, :file, :message, keyword_init: true) do
        def error?
          severity == :error
        end
      end

      Report = Struct.new(:problems, :references, :files, :seconds, keyword_init: true) do
        def errors
          problems.select(&:error?)
        end

        def warnings
          problems.reject(&:error?)
        end

        def ok?
          errors.empty?
        end
      end

      REFERENCE = /(\$)?\$\{([^}]+)\}/.freeze
      YAML_CLASSES = [Symbol, Date, Time].freeze
      EMPTY_HASH = {}.freeze
      EMPTY_SET = Set.new.freeze

      attr_reader :fallbacks, :default_fallbacks, :ignore_missing

      # @param paths [Array<String>] files, directories or globs
      # @param fallbacks [Hash{String => Array<String>}] extra fallbacks per locale
      # @param default_fallbacks [Array<String>] locales appended to every chain
      # @param ignore_missing [Array<String>] key globs whose absence is not an error
      def initialize(paths, fallbacks: {}, default_fallbacks: [], ignore_missing: [])
        @paths = Array(paths)
        @fallbacks = fallbacks.to_h { |k, v| [k.to_s, Array(v).map(&:to_s)] }
        @default_fallbacks = Array(default_fallbacks).map(&:to_s)
        @ignore_missing = Array(ignore_missing).map(&:to_s)
        @translations = {} # locale => { key => value }
        @origins = {}      # locale => { key => file }
        @scopes = {}       # locale => Set of keys that are hashes or arrays
        @problems = []
      end

      def run
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        files = expand_paths
        files.each { |file| load_file(file) }
        references = check_references
        check_cycles
        Report.new(
          problems: @problems.sort_by { |p| [p.file.to_s, p.locale, p.key] },
          references: references,
          files: files.size,
          seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        )
      end

      def chain(locale)
        @chains ||= {}
        @chains[locale] ||= begin
          parent = locale.include?('-') ? [locale.split('-').first] : []
          ([locale] + parent + fallbacks.fetch(locale, []) + default_fallbacks).uniq
        end
      end

      private

      def expand_paths
        @paths.flat_map { |path| expand_path(path) }.uniq.sort
      end

      # A path may be a file, a directory or a glob whose matches are themselves
      # files or directories (e.g. `packs/**/config/locales`).
      def expand_path(path)
        if File.directory?(path)
          Dir.glob(File.join(path, '**', '*.{yml,yaml}')).select { |f| File.file?(f) }
        elsif File.file?(path)
          [path]
        else
          Dir.glob(path).flat_map { |match| File.directory?(match) ? expand_path(match) : [match] }
        end
      end

      def load_file(file)
        data = YAML.safe_load(File.read(file), aliases: true, permitted_classes: YAML_CLASSES, filename: file)
        return unless data.is_a?(Hash)

        data.each do |locale, tree|
          next unless tree.is_a?(Hash)

          flatten(tree, [], locale.to_s, file)
        end
      rescue Psych::Exception, ArgumentError => e
        problem(:parse, :warning, nil, nil, file, "could not parse: #{e.message.lines.first&.strip}")
      end

      def flatten(tree, path, locale, file)
        tree.each do |k, v|
          current = path + [k.to_s]
          if v.is_a?(Hash)
            scopes_of(locale) << current.join('.')
            flatten(v, current, locale, file)
          else
            key = current.join('.')
            scopes_of(locale) << key if v.is_a?(Array)
            keys_of(locale)[key] = v
            (@origins[locale] ||= {})[key] = file
          end
        end
      end

      # Read access never creates locales, so iterating @translations is safe.
      def keys_of(locale, create: true)
        create ? (@translations[locale] ||= {}) : @translations.fetch(locale, EMPTY_HASH)
      end

      def scopes_of(locale, create: true)
        create ? (@scopes[locale] ||= Set.new) : @scopes.fetch(locale, EMPTY_SET)
      end

      def key_defined?(locale, key)
        keys_of(locale, create: false).key?(key)
      end

      def scope?(locale, key)
        scopes_of(locale, create: false).include?(key)
      end

      def check_references
        count = 0
        @translations.each do |locale, keys|
          keys.each do |key, value|
            each_string(value) do |string|
              scan(string).each do |ref, whole|
                count += 1
                check_reference(locale, key, ref, whole)
              end
            end
          end
        end
        count
      end

      def check_reference(locale, key, ref, whole)
        file = @origins[locale][key]
        found = chain(locale).find { |l| key_defined?(l, ref) || scope?(l, ref) }
        if found.nil?
          return if ignored?(ref)

          problem(:broken, :error, locale, key, file,
                  "broken reference ${#{ref}} (not found in #{chain(locale).join(', ')})")
        elsif !whole && scope?(found, ref)
          problem(:scope, :error, locale, key, file,
                  "reference ${#{ref}} is embedded in text but points to a hash or array")
        end
      end

      def check_cycles
        @translations.each_key do |locale|
          state = {}
          @translations[locale].each_key do |key|
            visit(locale, key, state, []) unless state[key]
          end
        end
      end

      # Iterative-friendly DFS with three states: nil (new), :active, :done.
      def visit(locale, key, state, stack)
        state[key] = :active
        stack.push(key)
        targets_of(locale, key).each do |ref|
          case state[ref]
          when :active
            cycle = stack[stack.index(ref)..] + [ref]
            problem(:cycle, :error, locale, cycle.first, @origins[locale][cycle.first],
                    "circular reference #{cycle.map { |k| "#{locale}.#{k}" }.join(' -> ')}")
          when nil
            visit(locale, ref, state, stack)
          end
        end
        stack.pop
        state[key] = :done
      end

      # Keys referenced from `key` as resolved from `locale` through its chain.
      def targets_of(locale, key)
        source = chain(locale).find { |l| key_defined?(l, key) }
        return [] unless source

        refs = []
        each_string(@translations[source][key]) { |s| refs.concat(scan(s).map(&:first)) }
        refs.select { |ref| chain(locale).any? { |l| key_defined?(l, ref) } }
      end

      def each_string(value, &block)
        case value
        when String then yield value
        when Array then value.each { |v| each_string(v, &block) }
        end
      end

      # Returns [[key, whole_string?], ...] skipping escaped `$${}` markers.
      def scan(string)
        return [] unless string.include?('${')

        refs = string.to_enum(:scan, REFERENCE).map { Regexp.last_match }
                     .reject { |m| m[1] }
                     .map { |m| m[2].strip }
        whole = refs.size == 1 && string.strip == "${#{refs.first}}"
        refs.map { |ref| [ref, whole] }
      end

      def ignored?(ref)
        ignore_missing.any? { |glob| File.fnmatch?(glob, ref, File::FNM_EXTGLOB) }
      end

      def problem(kind, severity, locale, key, file, message)
        @problems << Problem.new(kind: kind, severity: severity, locale: locale, key: key, file: file, message: message)
      end
    end
  end
end
