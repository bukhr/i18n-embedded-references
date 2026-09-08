# frozen_string_literal: true

require 'rake'
require_relative 'cli'

namespace :i18n do
  namespace :embedded_references do
    desc 'Check ${} references in locale files (PATHS="a b", CONFIG=file)'
    task :check do
      argv = ['check']
      argv.concat(ENV['PATHS'].to_s.split) if ENV['PATHS']
      argv.push('--config', ENV['CONFIG']) if ENV['CONFIG']
      status = I18n::EmbeddedReferences::CLI.new.run(argv)
      abort if status != 0
    end
  end
end
