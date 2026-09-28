# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'stringio'
require 'i18n/embedded_references/cli'

class CLITest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir('i18n-refs-cli')
    @out = StringIO.new
    @err = StringIO.new
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def write(name, content)
    File.write(File.join(@dir, name), content)
  end

  def run_cli(*argv, app_fallbacks: nil)
    I18n::EmbeddedReferences::CLI.new(out: @out, err: @err, app_fallbacks: app_fallbacks).run(argv)
  end

  def test_exit_zero_when_clean
    write('es.yml', "es:\n  name: Acme\n  hi: 'Hola ${name}'\n")
    assert_equal 0, run_cli('check', @dir)
    assert_match(/0 errors, 0 warnings, 1 references checked in 1 files/, @out.string)
  end

  def test_exit_one_with_errors_and_prints_them
    write('es.yml', "es:\n  hi: 'Hola ${nope}'\n")
    assert_equal 1, run_cli('check', @dir)
    assert_match(%r{#{Regexp.escape(@dir)}/es\.yml\n  es\.hi\n    error: broken reference \$\{nope\}}, @out.string)
    assert_match(/1 errors/, @out.string)
  end

  def test_quiet_only_prints_summary
    write('es.yml', "es:\n  hi: 'Hola ${nope}'\n")
    run_cli('check', @dir, '--quiet')
    assert_equal 1, @out.string.lines.size
  end

  def test_fallback_and_ignore_options
    write('es.yml', "es:\n  name: Acme\n")
    write('ca.yml', "ca:\n  hi: 'Hola ${name} ${custom.x}'\n")
    assert_equal 1, run_cli('check', @dir)
    assert_equal 0, run_cli('check', @dir, '--fallback', 'ca:es', '--ignore-missing', 'custom.*')
  end

  def test_default_fallback_option
    write('es.yml', "es:\n  name: Acme\n")
    write('en.yml', "en:\n  hi: 'Hello ${name}'\n")
    assert_equal 1, run_cli('check', @dir)
    assert_equal 0, run_cli('check', @dir, '--default-fallback', 'es')
  end

  def test_app_fallbacks_resolve_references
    write('es.yml', "es:\n  name: Acme\n")
    write('pt.yml', "pt:\n  hi: 'Ola ${name}'\n")
    assert_equal 1, run_cli('check', @dir)
    app = { chains: { 'pt' => %w[pt es] }, default_fallbacks: %w[es] }
    assert_equal 0, run_cli('check', @dir, app_fallbacks: app)
  end

  def test_flags_override_app_fallbacks_for_a_locale
    write('es.yml', "es:\n  name: Acme\n")
    write('pt.yml', "pt:\n  hi: 'Ola ${name}'\n")
    app = { chains: { 'pt' => %w[pt es] }, default_fallbacks: %w[es] }
    assert_equal 0, run_cli('check', @dir, app_fallbacks: app)
    # The override replaces the whole app chain, defaults included: `name`
    # only exists in `es`, which is no longer reachable from `pt`.
    assert_equal 1, run_cli('check', @dir, '--fallback', 'pt:en', app_fallbacks: app)
    assert_match(/not found in pt, en\)/, @out.string)
  end

  def test_app_defaults_apply_to_locales_without_an_app_chain
    write('es.yml', "es:\n  name: Acme\n")
    write('fr.yml', "fr:\n  hi: 'Salut ${name}'\n")
    app = { chains: { 'pt' => %w[pt es] }, default_fallbacks: %w[es] }
    assert_equal 0, run_cli('check', @dir, app_fallbacks: app)
  end

  def test_app_without_fallbacks_drops_the_regional_parent
    write('es.yml', "es:\n  name: Acme\n")
    write('es-CL.yml', "es-CL:\n  hi: 'Hola ${name}'\n")
    assert_equal 0, run_cli('check', @dir)
    app = { enabled: false, chains: {}, default_fallbacks: [] }
    assert_equal 1, run_cli('check', @dir, app_fallbacks: app)
    assert_equal 0, run_cli('check', @dir, '--fallback', 'es-CL:es', app_fallbacks: app)
  end

  def test_config_file
    write('es.yml', "es:\n  name: Acme\n")
    write('ca.yml', "ca:\n  hi: 'Hola ${name} ${custom.x}'\n")
    config = File.join(@dir, 'cfg.yml')
    File.write(config, "paths:\n  - #{@dir}\nfallbacks:\n  ca: [es]\nignore_missing:\n  - 'custom.*'\n")
    assert_equal 0, run_cli('check', '--config', config)
  end

  def test_unknown_command_is_usage_error
    assert_equal 2, run_cli('frobnicate')
    assert_match(/Usage/, @err.string)
  end

  def test_unknown_option_is_usage_error
    assert_equal 2, run_cli('check', '--bogus')
  end
end
