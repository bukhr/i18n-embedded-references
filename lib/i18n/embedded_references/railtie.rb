# frozen_string_literal: true

module I18n
  module EmbeddedReferences
    # Exposes `rake i18n:embedded_references:check` in Rails apps.
    class Railtie < Rails::Railtie
      rake_tasks do
        load File.expand_path('tasks.rb', __dir__)
      end
    end
  end
end
