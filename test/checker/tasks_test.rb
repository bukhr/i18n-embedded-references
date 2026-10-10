# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'rake'

class TasksTest < BackendTestCase
  def setup
    super
    @dir = Dir.mktmpdir('i18n-refs-rake')
    File.write(File.join(@dir, 'es.yml'), "es:\n  name: Acme\n")
    File.write(File.join(@dir, 'pt.yml'), "pt:\n  hi: 'Ola ${name}'\n")
    @previous_app = Rake.application
    Rake.application = Rake::Application.new
    load File.expand_path('../../lib/i18n/embedded_references/tasks.rb', __dir__)
    @env = { 'PATHS' => @dir, 'CONFIG' => nil, 'APP_FALLBACKS' => nil, 'IGNORE_MISSING' => nil }
  end

  def teardown
    Rake.application = @previous_app
    FileUtils.remove_entry(@dir)
    super
  end

  # Simulates a Rails app whose :environment task enables fallbacks to :es.
  def define_environment
    Rake::Task.define_task(:environment) do
      I18n.backend = FallbacksBackend.new
      I18n.available_locales = %i[es pt]
      I18n.fallbacks = [:es]
    end
  end

  def run_check(env = {})
    with_env(@env.merge(env)) do
      capture_io { Rake::Task['i18n:embedded_references:check'].invoke }
    end
  end

  def with_env(values)
    previous = values.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
    values.each { |k, v| ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| ENV[k] = v }
  end

  def test_uses_app_fallbacks_when_environment_is_defined
    define_environment
    out, = run_check
    assert_match(/Using fallbacks from I18n.fallbacks \(2 locales, defaults: es\)/, out)
    assert_match(/0 errors/, out)
  end

  # Simulates a Rails app booted without `config.i18n.fallbacks`.
  def test_app_without_fallbacks_checks_without_fallbacks
    Rake::Task.define_task(:environment) { I18n.backend = Backend.new }
    File.write(File.join(@dir, 'pt.yml'), "pt:\n  other: 'x'\n")
    File.write(File.join(@dir, 'es-CL.yml'), "es-CL:\n  hi: 'Hola ${name}'\n")
    out, = with_env(@env) do
      capture_io { assert_raises(SystemExit) { Rake::Task['i18n:embedded_references:check'].invoke } }
    end
    assert_match(/App backend does not use I18n::Backend::Fallbacks \(RAILS_ENV=\S+\): checking without fallbacks/,
                 out)
    assert_match(/es-CL\.hi\n    error: broken reference \$\{name\} \(not found in es-CL\)/, out)
  end

  def test_app_fallbacks_can_be_disabled
    define_environment
    assert_raises(SystemExit) { run_check('APP_FALLBACKS' => 'false') }
  end

  def test_ignore_missing_env
    define_environment
    File.write(File.join(@dir, 'es.yml'), "es:\n  name: Acme\n  x: '${custom.a} ${other.b}'\n")
    assert_raises(SystemExit) { run_check('IGNORE_MISSING' => 'custom.*') }
    Rake::Task['i18n:embedded_references:check'].reenable
    out, = run_check('IGNORE_MISSING' => 'custom.* other.*')
    assert_match(/0 errors/, out)
  end

  def test_without_environment_task_behaves_like_the_cli
    assert_raises(SystemExit) { run_check }
  end
end
