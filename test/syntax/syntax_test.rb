# frozen_string_literal: true

require 'minitest/autorun'
require 'i18n/embedded_references/syntax'

class SyntaxTest < Minitest::Test
  Syntax = I18n::EmbeddedReferences::Syntax
  Ref = Syntax::Reference

  def test_plain_string_is_one_literal
    assert_equal ['hello'], Syntax.tokenize('hello')
    refute Syntax.markers?('hello')
  end

  def test_references_and_text_keep_their_order
    assert_equal ['Hi ', Ref.new('user.name'), ', see ', Ref.new('a')], Syntax.tokenize('Hi ${user.name}, see ${a}')
  end

  def test_escape_is_literal_text
    assert_equal ['write ', '${name}', ' here'], Syntax.tokenize('write $${name} here')
  end

  def test_empty_braces_and_unclosed_markers_are_text
    assert_equal ['${}'], Syntax.tokenize('${}')
    assert_equal ['${open'], Syntax.tokenize('${open')
  end

  def test_key_is_taken_verbatim
    assert_equal [Ref.new(' name ')], Syntax.tokenize('${ name }')
  end

  def test_reference_without_transforms
    ref = Syntax.tokenize('${name}').first
    assert_equal [], ref.transforms
    refute ref.transforms?
  end

  def test_transforms_are_split_off_the_key_in_order
    assert_equal [Ref.new('name', ['upcase'])], Syntax.tokenize('${name|upcase}')
    assert_equal [Ref.new('user.name', %w[downcase upcase_first])],
                 Syntax.tokenize('${user.name|downcase|upcase_first}')
    assert Syntax.tokenize('${name|upcase}').first.transforms?
  end

  def test_transform_names_are_taken_verbatim
    assert_equal [Ref.new('name', [' upcase'])], Syntax.tokenize('${name| upcase}')
    assert_equal [Ref.new('name', [''])], Syntax.tokenize('${name|}')
    assert_equal [Ref.new('', ['upcase'])], Syntax.tokenize('${|upcase}')
  end

  def test_marker_is_the_reference_as_written
    assert_equal '${name}', Ref.new('name').marker
    assert_equal '${name|downcase|upcase_first}', Syntax.tokenize('${name|downcase|upcase_first}').first.marker
  end

  def test_escaped_reference_with_transform_is_literal_text
    assert_equal ['${name|upcase}'], Syntax.tokenize('$${name|upcase}')
  end

  def test_single_reference
    assert Syntax.single_reference?(Syntax.tokenize('${menu}'))
    assert Syntax.single_reference?(Syntax.tokenize('${menu|upcase}'))
    refute Syntax.single_reference?(Syntax.tokenize(' ${menu}'))
    refute Syntax.single_reference?(Syntax.tokenize('${a}${b}'))
    refute Syntax.single_reference?(Syntax.tokenize('$${menu}'))
  end
end
