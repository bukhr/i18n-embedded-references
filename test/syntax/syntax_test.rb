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

  def test_single_reference
    assert Syntax.single_reference?(Syntax.tokenize('${menu}'))
    refute Syntax.single_reference?(Syntax.tokenize(' ${menu}'))
    refute Syntax.single_reference?(Syntax.tokenize('${a}${b}'))
    refute Syntax.single_reference?(Syntax.tokenize('$${menu}'))
  end
end
