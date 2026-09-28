# frozen_string_literal: true

require 'rake'
require_relative 'cli'
require_relative 'app_fallbacks'

namespace :i18n do
  namespace :embedded_references do
    desc 'Check ${} references in locale files ' \
         '(PATHS="a b", IGNORE_MISSING="glob ...", CONFIG=file, APP_FALLBACKS=false)'
    task :check do
      # In a Rails app, boot it and mirror I18n.fallbacks so references are
      # resolved like at runtime. APP_FALLBACKS=false skips booting the app.
      app_fallbacks = nil
      if ENV['APP_FALLBACKS'] != 'false' && Rake::Task.task_defined?(:environment)
        Rake::Task[:environment].invoke
        app_fallbacks = I18n::EmbeddedReferences::AppFallbacks.from_i18n
        puts I18n::EmbeddedReferences::AppFallbacks.describe(app_fallbacks)
      end

      argv = ['check']
      argv.concat(ENV['PATHS'].to_s.split) if ENV['PATHS']
      argv.push('--config', ENV['CONFIG']) if ENV['CONFIG']
      ENV['IGNORE_MISSING'].to_s.split.each { |glob| argv.push('--ignore-missing', glob) }
      status = I18n::EmbeddedReferences::CLI.new(app_fallbacks: app_fallbacks).run(argv)
      abort if status != 0
    end
  end
end
