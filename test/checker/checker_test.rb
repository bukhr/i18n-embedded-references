# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'i18n/embedded_references/checker'

class CheckerTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir('i18n-refs')
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def write(name, content)
    path = File.join(@dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def check(**opts)
    I18n::EmbeddedReferences::Checker.new([@dir], **opts).run
  end

  def kinds(report)
    report.problems.map(&:kind)
  end

  def test_clean_files_report_no_problems
    write('es.yml', "es:\n  name: Acme\n  hi: 'Hola ${name}'\n  menu: { a: 'x', b: 'y' }\n  alias: '${menu}'\n")
    report = check
    assert report.ok?
    assert_empty report.problems
    assert_equal 2, report.references
    assert_equal 1, report.files
  end

  def test_broken_reference_is_an_error
    write('es.yml', "es:\n  hi: 'Hola ${nope}'\n")
    report = check
    refute report.ok?
    assert_equal [:broken], kinds(report)
    problem = report.problems.first
    assert_equal 'es', problem.locale
    assert_equal 'hi', problem.key
    assert_match(/\$\{nope\}.*not found in es/, problem.message)
    assert_equal File.join(@dir, 'es.yml'), problem.file
  end

  def test_reference_found_through_default_regional_fallback
    write('es.yml', "es:\n  name: Acme\n")
    write('es-CL.yml', "es-CL:\n  hi: 'Hola ${name}'\n")
    assert check.ok?
  end

  def test_reference_found_through_configured_fallback
    write('es.yml', "es:\n  name: Acme\n")
    write('ca.yml', "ca:\n  hi: 'Hola ${name}'\n")
    refute check.ok?
    assert check(fallbacks: { 'ca' => ['es'] }).ok?
  end

  def test_default_fallbacks_apply_to_every_locale
    write('es.yml', "es:\n  name: Acme\n")
    write('en.yml', "en:\n  hi: 'Hello ${name}'\n")
    write('pt-BR.yml', "pt-BR:\n  hi: 'Ola ${name}'\n")
    refute check.ok?
    assert check(default_fallbacks: ['es']).ok?
  end

  def test_ignore_missing_globs
    write('es.yml', "es:\n  hi: 'Hola ${custom.models.employee.one} y ${nope}'\n")
    report = check(ignore_missing: ['custom.*'])
    assert_equal 1, report.errors.size
    assert_match(/\$\{nope\}/, report.errors.first.message)
  end

  def test_escaped_reference_is_not_checked
    write('es.yml', "es:\n  doc: 'usa $${nope} para escapar'\n")
    report = check
    assert report.ok?
    assert_equal 0, report.references
  end

  def test_cycle_is_an_error
    write('es.yml', "es:\n  a: 'x ${b}'\n  b: 'y ${c}'\n  c: 'z ${a}'\n")
    report = check
    assert_equal [:cycle], kinds(report)
    assert_match(/es\.a -> es\.b -> es\.c -> es\.a/, report.problems.first.message)
  end

  def test_self_reference_is_a_cycle
    write('es.yml', "es:\n  a: 'x ${a}'\n")
    assert_equal [:cycle], kinds(check)
  end

  def test_cycle_through_fallback_locale
    write('es.yml', "es:\n  a: '${b}'\n  b: '${a}'\n")
    write('es-CL.yml', "es-CL:\n  a: '${b}'\n")
    report = check
    assert_equal(2, report.problems.count { |p| p.kind == :cycle })
    assert_includes report.problems.map(&:locale), 'es-CL'
  end

  def test_diamond_reference_is_not_a_cycle
    write('es.yml', "es:\n  base: 'v'\n  x: '${base}'\n  y: '${base}'\n  top: '${x} ${y}'\n")
    assert check.ok?
  end

  def test_embedded_reference_to_scope_is_an_error
    write('es.yml', "es:\n  menu: { a: 'x' }\n  bad: 'Ver ${menu}'\n  good: '${menu}'\n")
    report = check
    assert_equal [:scope], kinds(report)
    assert_equal 'bad', report.problems.first.key
  end

  def test_embedded_reference_to_array_is_an_error
    write('es.yml', "es:\n  days: [lun, mar]\n  bad: 'Dias: ${days}'\n")
    assert_equal [:scope], kinds(check)
  end

  def test_references_inside_arrays_are_checked
    write('es.yml', "es:\n  name: Acme\n  list:\n    - 'Hola ${name}'\n    - 'Chao ${nope}'\n")
    report = check
    assert_equal [:broken], kinds(report)
    assert_equal 'list', report.problems.first.key
  end

  def test_unparseable_file_is_a_warning
    write('bad.yml', "es:\n  a: [unclosed\n")
    write('es.yml', "es:\n  ok: 'fine'\n")
    report = check
    assert report.ok?
    assert_equal [:parse], kinds(report)
    assert_equal :warning, report.problems.first.severity
  end

  def test_accepts_files_and_globs
    write('a/es.yml', "es:\n  name: Acme\n")
    write('b/es.yml', "es:\n  hi: 'Hola ${name}'\n")
    report = I18n::EmbeddedReferences::Checker.new([File.join(@dir, 'a', 'es.yml'), File.join(@dir, 'b', '*.yml')]).run
    assert report.ok?
    assert_equal 2, report.files
  end

  def test_glob_matching_directories_is_expanded
    write('packs/a/config/locales/es.yml', "es:\n  name: Acme\n")
    write('packs/b/config/locales/es.yml', "es:\n  hi: 'Hola ${name}'\n")
    report = I18n::EmbeddedReferences::Checker.new([File.join(@dir, 'packs', '*', 'config', 'locales')]).run
    assert report.ok?
    assert_equal 2, report.files
  end

  def test_chain_dedups_and_orders
    checker = I18n::EmbeddedReferences::Checker.new([], fallbacks: { 'es-CL' => %w[es en] }, default_fallbacks: ['es'])
    assert_equal %w[es-CL es en], checker.chain('es-CL')
    assert_equal %w[pt es], checker.chain('pt')
    assert_equal %w[es], checker.chain('es')
  end

  def test_app_chains_are_used_in_their_own_order
    checker = I18n::EmbeddedReferences::Checker.new([], app_chains: { 'de-AT' => %w[de-AT de-DE de] },
                                                        app_default_fallbacks: %w[en])
    assert_equal %w[de-AT de-DE de], checker.chain('de-AT')
    assert_equal %w[fr-CA fr en], checker.chain('fr-CA')
  end

  # A custom I18n.fallbacks whose #[] does not include its #defaults: the chain
  # is authoritative, so a key reachable only through the defaults is broken.
  def test_app_defaults_are_not_appended_to_an_app_chain
    write('es.yml', "es:\n  name: Acme\n")
    write('pt.yml', "pt:\n  hi: 'Ola ${name}'\n")
    report = check(app_chains: { 'pt' => %w[pt en] }, app_default_fallbacks: %w[es])
    assert_equal [:broken], kinds(report)
    assert_match(/not found in pt, en\)/, report.problems.first.message)
  end

  def test_app_chain_starts_with_the_locale
    checker = I18n::EmbeddedReferences::Checker.new([], app_chains: { 'de-AT' => %w[de-DE de] })
    assert_equal %w[de-AT de-DE de], checker.chain('de-AT')
  end

  def test_configured_fallbacks_override_app_chain_and_defaults
    checker = I18n::EmbeddedReferences::Checker.new([], fallbacks: { 'pt' => %w[en] }, default_fallbacks: %w[fr],
                                                        app_chains: { 'pt' => %w[pt es] },
                                                        app_default_fallbacks: %w[es])
    assert_equal %w[pt en fr], checker.chain('pt')
  end

  def test_app_chain_order_decides_which_target_is_checked
    write('de-DE.yml', "de-DE:\n  thing: 'Ding'\n")
    write('de.yml', "de:\n  thing: { a: 'x' }\n")
    write('de-AT.yml', "de-AT:\n  hi: 'Servus ${thing}'\n")
    assert_equal [:scope], kinds(check(fallbacks: { 'de-AT' => %w[de-DE] }))
    assert check(app_chains: { 'de-AT' => %w[de-AT de-DE de] }).ok?
  end

  # The app runs without I18n::Backend::Fallbacks: `es-CL` does not fall back
  # to `es` at runtime, so only explicit user defaults make `name` reachable.
  def test_app_fallbacks_disabled_drops_the_regional_parent
    write('es.yml', "es:\n  name: Acme\n")
    write('es-CL.yml', "es-CL:\n  hi: 'Hola ${name}'\n")
    report = check(app_fallbacks_disabled: true)
    assert_equal [:broken], kinds(report)
    assert_match(/not found in es-CL\)/, report.problems.first.message)
    assert check(app_fallbacks_disabled: true, default_fallbacks: ['es']).ok?
  end

  def test_app_fallbacks_disabled_chain
    checker = I18n::EmbeddedReferences::Checker.new([], app_fallbacks_disabled: true,
                                                        fallbacks: { 'pt-BR' => %w[en] })
    assert_equal %w[es-CL], checker.chain('es-CL')
    assert_equal %w[pt-BR pt en], checker.chain('pt-BR')
  end
end
