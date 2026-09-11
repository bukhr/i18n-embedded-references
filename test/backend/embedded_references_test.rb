# frozen_string_literal: true

require 'test_helper'

class EmbeddedReferencesTest < BackendTestCase
  def test_plain_translation_is_untouched
    store(:en, greeting: 'hello')
    assert_equal 'hello', I18n.t(:greeting)
  end

  def test_reference_inside_string
    store(:en, name: 'world', greeting: 'hello ${name}')
    assert_equal 'hello world', I18n.t(:greeting)
  end

  def test_multiple_references_and_dotted_keys
    store(:en, user: { first: 'Ada', last: 'Lovelace' }, full: '${user.first} ${user.last}')
    assert_equal 'Ada Lovelace', I18n.t(:full)
  end

  def test_nested_references_resolve_recursively
    store(:en, a: 'A', b: 'b ${a}', c: 'c ${b}', d: 'd ${c}')
    assert_equal 'd c b A', I18n.t(:d)
  end

  def test_escaped_reference_is_literal
    store(:en, name: 'world', doc: 'write $${name} to embed')
    assert_equal 'write ${name} to embed', I18n.t(:doc)
  end

  def test_single_reference_to_hash_returns_hash
    store(:en, colors: { red: 'Red', blue: 'Blue' }, alias: '${colors}')
    assert_equal({ red: 'Red', blue: 'Blue' }, I18n.t(:alias))
  end

  def test_single_reference_to_array_returns_array
    store(:en, days: %w[mon tue], alias: '${days}')
    assert_equal %w[mon tue], I18n.t(:alias)
  end

  def test_broken_reference_inside_hash_only_affects_that_element
    store(:en, name: 'Alice', messages: { hi: 'hi ${name}', bad: 'x ${nope}' })
    result = I18n.t(:messages)
    assert_equal 'hi Alice', result[:hi]
    assert_match(/translation missing: en\.nope/i, result[:bad])
  end

  def test_broken_reference_inside_array_only_affects_that_element
    store(:en, name: 'Alice', list: ['hi ${name}', 'x ${nope}'])
    result = I18n.t(:list)
    assert_equal 'hi Alice', result[0]
    assert_match(/translation missing: en\.nope/i, result[1])
  end

  def test_hash_values_are_resolved
    store(:en, name: 'Alice', messages: { hi: 'hi ${name}', bye: 'bye ${name}' })
    assert_equal({ hi: 'hi Alice', bye: 'bye Alice' }, I18n.t(:messages))
  end

  def test_array_values_are_resolved
    store(:en, name: 'Alice', list: ['hi ${name}', 'bye ${name}', 'plain'])
    assert_equal ['hi Alice', 'bye Alice', 'plain'], I18n.t(:list)
  end

  def test_deeply_nested_structures_are_resolved
    store(:en, base: 'v', nested: { items: ['${base} 1', { deep: '${base} 2' }], data: { key: '${base}' } })
    assert_equal({ items: ['v 1', { deep: 'v 2' }], data: { key: 'v' } }, I18n.t(:nested))
  end

  def test_store_is_not_mutated
    store(:en, name: 'Alice', messages: { hi: 'hi ${name}' })
    I18n.t(:messages)
    assert_equal 'hi ${name}', I18n.backend.send(:translations)[:en][:messages][:hi]
    store(:en, name: 'Bob')
    assert_equal 'hi Bob', I18n.t(:'messages.hi')
  end

  def test_referenced_value_is_interpolated_with_caller_values
    store(:en, body: 'Dear %{who}', letter: '${body}, bye')
    assert_equal 'Dear Ann, bye', I18n.t(:letter, who: 'Ann')
  end

  def test_referenced_value_is_pluralized
    store(:en, count_msg: { one: 'one item', other: '%{count} items' }, wrap: '[${count_msg}]')
    assert_equal '[3 items]', I18n.t(:wrap, count: 3)
  end

  def test_missing_reference_makes_the_translation_missing
    store(:en, greeting: 'hello ${nope}')
    assert_equal 'translation missing: en.nope', I18n.t(:greeting).downcase
  end

  def test_missing_reference_throws_when_throw_option_given
    store(:en, greeting: 'hello ${nope}')
    caught = catch(:exception) { I18n.t(:greeting, throw: true) }
    assert_kind_of I18n::MissingTranslation, caught
  end

  def test_referenced_value_missing_interpolation_argument_raises
    store(:en, body: 'Dear %{who}', letter: '${body}, bye')
    assert_raises(I18n::MissingInterpolationArgument) { I18n.t(:letter, other: 1) }
  end

  def test_scope_is_not_forwarded_to_references
    store(:en, name: 'root', admin: { greeting: 'hi ${name}' })
    assert_equal 'hi root', I18n.t(:greeting, scope: :admin)
  end

  def test_missing_reference_raises_when_raise_option_given
    store(:en, greeting: 'hello ${nope}')
    assert_raises(I18n::MissingTranslationData) { I18n.t(:greeting, raise: true) }
  end

  def test_circular_reference_raises
    store(:en, a: '${b}', b: '${c}', c: '${a}')
    error = assert_raises(I18n::Backend::EmbeddedReferences::CircularReferenceError) { I18n.t(:a) }
    assert_equal 'circular embedded reference: en.b -> en.c -> en.a -> en.b', error.message
  end

  def test_self_reference_raises
    store(:en, a: 'x ${a}')
    assert_raises(I18n::Backend::EmbeddedReferences::CircularReferenceError) { I18n.t(:a) }
  end

  def test_resolution_state_is_cleared_after_error
    store(:en, a: '${a}', ok: 'fine')
    assert_raises(I18n::Backend::EmbeddedReferences::CircularReferenceError) { I18n.t(:a) }
    assert_equal 'fine', I18n.t(:ok)
    assert_nil Thread.current[:i18n_embedded_references_stack]
    assert_nil Thread.current[:i18n_embedded_references_requested_locale]
  end

  def test_explicit_locale_option_is_used_for_references
    store(:en, name: 'world', greeting: 'hello ${name}')
    store(:de, name: 'Welt', greeting: 'hallo ${name}')
    assert_equal 'hallo Welt', I18n.t(:greeting, locale: :de)
    assert_equal 'hello world', I18n.t(:greeting)
  end

  def test_translate_with_scope_option
    store(:en, admin: { name: 'root', greeting: 'hi ${admin.name}' })
    assert_equal 'hi root', I18n.t(:greeting, scope: :admin)
  end

  def test_symbol_links_still_work
    store(:en, name: 'world', greeting: 'hello ${name}', link: :greeting)
    assert_equal 'hello world', I18n.t(:link)
  end
end

class EmbeddedReferencesFallbacksTest < BackendTestCase
  def setup
    super
    I18n.backend = FallbacksBackend.new
    I18n.available_locales = %i[en en-CL]
    I18n.fallbacks = [:en]
    store(:en, name: 'notice', greeting: { alert: 'alert ${name}' }, only_en: 'en ${name}')
    store(:'en-CL', name: 'notice-cl')
  end

  def test_reference_found_via_fallback_resolves_in_requested_locale
    I18n.locale = :'en-CL'
    assert_equal 'alert notice-cl', I18n.t(:'greeting.alert')
    assert_equal({ alert: 'alert notice-cl' }, I18n.t(:greeting))
  end

  def test_reference_uses_explicit_locale_option_over_current_locale
    I18n.locale = :en
    assert_equal 'en notice-cl', I18n.t(:only_en, locale: :'en-CL')
  end

  def test_reference_falls_back_when_missing_in_requested_locale
    store(:'en-CL', other: 'other ${greeting.alert}')
    I18n.locale = :'en-CL'
    assert_equal 'other alert notice-cl', I18n.t(:other)
  end
end

class EmbeddedReferencesFallbacksOnChainTest < BackendTestCase
  def setup
    super
    simple = Backend.new
    simple.store_translations(:en, name: 'notice', greeting: { alert: 'alert ${name}' }, only_en: 'en ${name}')
    simple.store_translations(:en, a: 'en-a', b: 'en-b', pair: '${a} ${b}', pair_hash: { x: '${a}', y: '${b}' })
    simple.store_translations(:'en-CL', name: 'notice-cl', a: 'cl-a', b: 'cl-b')
    I18n.backend = FallbacksChain.new(Backend.new, simple)
    I18n.available_locales = %i[en en-CL]
    I18n.fallbacks = [:en]
  end

  def test_reference_found_via_fallback_resolves_in_requested_locale
    I18n.locale = :'en-CL'
    assert_equal 'alert notice-cl', I18n.t(:'greeting.alert')
    assert_equal({ alert: 'alert notice-cl' }, I18n.t(:greeting))
  end

  def test_explicit_locale_wins_over_thread_locale
    I18n.locale = :en
    assert_equal 'en notice-cl', I18n.t(:only_en, locale: :'en-CL')
  end

  def test_explicit_locale_is_kept_for_every_reference_in_a_string
    I18n.locale = :en
    assert_equal 'cl-a cl-b', I18n.t(:pair, locale: :'en-CL')
  end

  def test_explicit_locale_is_kept_for_every_reference_in_a_hash
    I18n.locale = :en
    assert_equal({ x: 'cl-a', y: 'cl-b' }, I18n.t(:pair_hash, locale: :'en-CL'))
  end
end

class EmbeddedReferencesChainTest < BackendTestCase
  def test_references_resolve_across_chained_backends
    first = Backend.new
    second = Backend.new
    first.store_translations(:en, greeting: 'hello ${name}')
    second.store_translations(:en, name: 'from second')
    I18n.backend = I18n::Backend::Chain.new(first, second)
    assert_equal 'hello from second', I18n.t(:greeting)
  end
end

class EmbeddedReferencesEntryPointTest < Minitest::Test
  def test_gem_name_is_requirable
    assert require('i18n-embedded-references') || defined?(I18n::Backend::EmbeddedReferences)
  end
end
