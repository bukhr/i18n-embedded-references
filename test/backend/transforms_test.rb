# frozen_string_literal: true

require 'test_helper'

class TransformsTest < BackendTestCase
  TransformError = I18n::Backend::EmbeddedReferences::TransformError

  def test_each_transform
    store(:en, name: 'jefe de Área', greeting: 'hello ${name|%s}')
    {
      'upcase' => 'JEFE DE ÁREA',
      'downcase' => 'jefe de área',
      'capitalize' => 'Jefe de área',
      'upcase_first' => 'Jefe de Área',
      'downcase_first' => 'jefe de Área'
    }.each do |transform, expected|
      store(:en, greeting: "hello ${name|#{transform}}")
      assert_equal "hello #{expected}", I18n.t(:greeting), transform
    end
  end

  def test_transforms_chain_left_to_right
    store(:en, name: 'ADA LOVELACE', greeting: 'hi ${name|downcase|upcase_first}')
    assert_equal 'hi Ada lovelace', I18n.t(:greeting)
  end

  def test_single_reference_with_transform_returns_a_string
    store(:en, name: 'ada', upper: '${name|upcase}')
    assert_equal 'ADA', I18n.t(:upper)
  end

  def test_nested_references_are_resolved_before_the_transform
    store(:en, a: 'x', b: '${a} y', c: '${b|upcase}')
    assert_equal 'X Y', I18n.t(:c)
  end

  def test_transforms_apply_inside_hashes_and_arrays
    store(:en, name: 'ada', messages: { hi: 'hi ${name|upcase_first}' }, list: ['${name|upcase}'])
    assert_equal({ hi: 'hi Ada' }, I18n.t(:messages))
    assert_equal ['ADA'], I18n.t(:list)
  end

  def test_placeholders_survive_the_transform_when_not_interpolated
    store(:en, body: 'dear %{name}, %<count>d items, 100%%', shout: '${body|upcase}')
    assert_equal 'DEAR %{name}, %<count>d ITEMS, 100%%', I18n.t(:shout)
  end

  def test_first_character_transforms_leave_a_leading_placeholder_alone
    store(:en, body: '%{name} is here', text: '${body|upcase_first}')
    assert_equal '%{name} is here', I18n.t(:text)
  end

  def test_capitalize_keeps_one_state_across_placeholders
    store(:en, body: 'hello%{name}WORLD', text: '${body|capitalize}')
    assert_equal 'Hello%{name}world', I18n.t(:text)
  end

  def test_pluralization_hash_is_transformed_after_pluralizing
    store(:en, items: { one: 'one item', other: '%{count} items' }, label: '${items|upcase}')
    assert_equal '2 ITEMS', I18n.t(:label, count: 2)
    assert_equal 'ONE ITEM', I18n.t(:label, count: 1)
    assert_raises(TransformError) { I18n.t(:label) }
  end

  def test_transform_on_a_non_text_scalar_raises
    store(:en, total: 3, flag: true, text: '${total|upcase}', other: '${flag|upcase}')
    assert_raises(TransformError) { I18n.t(:text) }
    assert_raises(TransformError) { I18n.t(:other) }
  end

  def test_interpolated_values_are_transformed_with_the_text
    store(:en, body: 'dear %{name}', shout: '${body|upcase}')
    assert_equal 'DEAR ADA', I18n.t(:shout, name: 'Ada')
  end

  def test_escaped_reference_with_transform_is_literal
    store(:en, doc: 'write $${name|upcase}')
    assert_equal 'write ${name|upcase}', I18n.t(:doc)
  end

  def test_unknown_transform_raises_even_when_the_key_is_missing
    store(:en, text: 'hi ${nope|shout}')
    error = assert_raises(TransformError) { I18n.t(:text) }
    assert_equal 'unknown transform "shout" in ${nope|shout}', error.message
  end

  def test_unknown_transform_names_the_first_unknown_in_a_chain
    store(:en, name: 'ada', text: 'hi ${name|upcase|shout|loud}')
    error = assert_raises(TransformError) { I18n.t(:text) }
    assert_match(/unknown transform "shout"/, error.message)
  end

  def test_transform_on_a_hash_or_array_raises
    store(:en, menu: { a: 'x' }, days: %w[mon], text: '${menu|upcase}', list: '${days|upcase}')
    error = assert_raises(TransformError) { I18n.t(:text) }
    assert_equal '${menu|upcase} cannot transform a hash or array', error.message
    assert_raises(TransformError) { I18n.t(:list) }
  end

  def test_broken_reference_with_a_known_transform_is_a_missing_translation
    store(:en, text: 'hi ${nope|upcase}')
    assert_match(/translation missing: en\.nope/i, I18n.t(:text))
    assert_raises(I18n::MissingTranslationData) { I18n.t(:text, raise: true) }
  end

  def test_transform_uses_the_requested_locale
    I18n.backend = FallbacksBackend.new
    I18n.fallbacks = [:en]
    store(:en, name: 'notice', alert: 'alert ${name|upcase}')
    store(:'en-CL', name: 'notice-cl')
    assert_equal 'alert NOTICE-CL', I18n.t(:alert, locale: :'en-CL')
  end
end
