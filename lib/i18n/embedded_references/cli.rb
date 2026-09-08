# frozen_string_literal: true

require 'optparse'
require 'yaml'
require_relative 'checker'

module I18n
  module EmbeddedReferences
    # Command line front end for Checker.
    #
    #   i18n-embedded-references check [paths...] [--config FILE]
    #     [--fallback LOCALE:PARENT[,PARENT]] [--default-fallback LOCALE]
    #     [--ignore-missing GLOB] [--quiet]
    #
    # Exit status: 0 clean, 1 errors found, 2 usage error.
    class CLI
      CONFIG_FILE = '.i18n-embedded-references.yml'
      DEFAULT_PATHS = ['config/locales'].freeze

      def initialize(out: $stdout, err: $stderr)
        @out = out
        @err = err
      end

      def run(argv)
        argv = argv.dup
        command = argv.shift
        return usage(2) unless command == 'check'

        options = parse(argv)
        return options if options.is_a?(Integer)

        report = Checker.new(options[:paths], fallbacks: options[:fallbacks],
                                              default_fallbacks: options[:default_fallbacks],
                                              ignore_missing: options[:ignore_missing]).run
        print_report(report, quiet: options[:quiet])
        report.ok? ? 0 : 1
      rescue OptionParser::ParseError => e
        @err.puts e.message
        usage(2)
      end

      private

      def parse(argv)
        options = { fallbacks: {}, default_fallbacks: [], ignore_missing: [], quiet: false, config: nil }
        parser = build_parser(options)
        paths = parser.parse(argv)
        return 0 if options[:help]

        merge_config(options, paths)
      end

      def build_parser(options)
        OptionParser.new do |o|
          o.banner = 'Usage: i18n-embedded-references check [paths...] [options]'
          o.on('-c', '--config FILE', "config file (default: #{CONFIG_FILE} if present)") { |f| options[:config] = f }
          o.on('-f', '--fallback SPEC', 'LOCALE:PARENT[,PARENT] (repeatable)') do |spec|
            locale, parents = spec.split(':', 2)
            options[:fallbacks][locale] = parents.to_s.split(',')
          end
          o.on('-d', '--default-fallback LOCALE', 'fallback appended to every locale (repeatable)') do |l|
            options[:default_fallbacks] << l
          end
          o.on('-i', '--ignore-missing GLOB', 'key glob whose absence is not an error (repeatable)') do |g|
            options[:ignore_missing] << g
          end
          o.on('-q', '--quiet', 'only print the summary line') { options[:quiet] = true }
          o.on('-h', '--help') do
            @out.puts o
            options[:help] = true
          end
        end
      end

      # Command line values win over the config file; lists are concatenated.
      def merge_config(options, paths)
        config = load_config(options[:config])
        config.fetch('fallbacks', {}).each { |l, p| options[:fallbacks][l.to_s] ||= Array(p).map(&:to_s) }
        %i[default_fallbacks ignore_missing].each { |k| options[k] = list(config, k.to_s) + options[k] }
        options[:paths] = paths.empty? ? list(config, 'paths') : paths
        options[:paths] = DEFAULT_PATHS if options[:paths].empty?
        options
      end

      def load_config(path)
        file = path || (File.exist?(CONFIG_FILE) ? CONFIG_FILE : nil)
        return {} unless file

        YAML.safe_load(File.read(file), filename: file) || {}
      end

      def list(config, key)
        Array(config[key]).map(&:to_s)
      end

      def print_report(report, quiet:)
        unless quiet
          report.problems.group_by(&:file).each do |file, problems|
            @out.puts file || '(no file)'
            problems.each do |p|
              @out.puts "  #{[p.locale, p.key].compact.join('.')}" if p.key
              @out.puts "    #{p.severity}: #{p.message}"
            end
            @out.puts
          end
        end
        @out.puts format('%<e>d errors, %<w>d warnings, %<r>d references checked in %<f>d files (%<s>.1fs)',
                         e: report.errors.size, w: report.warnings.size, r: report.references,
                         f: report.files, s: report.seconds)
      end

      def usage(status)
        @err.puts 'Usage: i18n-embedded-references check [paths...] [options]'
        status
      end
    end
  end
end
