const quantifierRule = prefix => $ => seq(
  prefix($),
  optional(alias('?', $.lazy))
)

const SYNTAX_CHARS = [
  ...'^$\\.*+?()[]|'
]

const SYNTAX_CHARS_ESCAPED = SYNTAX_CHARS.map(
  char => `\\${char}`
).join('')

module.exports = grammar({
  name: 'regex',

  extras: $ => [/\r?\n/],

  inline: $ => [
    $._character_escape,
    $._class_atom,
  ],

  conflicts: $ => [[$.character_class, $.class_range]],

  rules: {
    pattern: $ => choice(
      $.alternation,
      $.term,
    ),

    alternation: $ => seq(
      optional($.term),
      repeat1(seq('|', optional($.term)))
    ),

    term: $ => repeat1(seq(
      choice(
        $.start_assertion,
        $.end_assertion,
        $.boundary_assertion,
        $.non_boundary_assertion,
        $.lookaround_assertion,
        $.pattern_character,
        $.character_class,
        $.any_character,
        $.decimal_escape,
        $.character_class_escape,
        $._character_escape,
        $.backreference_escape,
        $.anonymous_capturing_group,
        $.named_capturing_group,
        $.non_capturing_group,
      ),
      optional(choice(
        $.zero_or_more,
        $.one_or_more,
        $.optional,
        $.count_quantifier,
      ))
    )),

    any_character: $ => '.',

    start_assertion: $ => '^',
    end_assertion: $ => '$',
    boundary_assertion: $ => '\\b',
    non_boundary_assertion: $ => '\\B',
    lookaround_assertion: $ => choice(
      $._lookahead_assertion,
      $._lookbehind_assertion
    ),
    _lookahead_assertion: $ => seq(
      '(?',
      choice('=', '!'),
      $.pattern,
      ')'
    ),
    _lookbehind_assertion: $ => seq(
      '(?<',
      choice('=', '!'),
      $.pattern,
      ')'
    ),

    pattern_character: $ => new RegExp(`[^${SYNTAX_CHARS_ESCAPED}\\r?\\n]`),

    character_class: $ => seq(
      '[',
      optional('^'),
      repeat(choice(
        $.class_range,
        $._class_atom
      )),
      ']'
    ),

    class_range: $ => prec.right(
      seq($._class_atom, '-', $._class_atom)
    ),

    _class_atom: $ => choice(
      alias('-', $.class_character),
      $.class_character,
      alias('\\-', $.identity_escape),
      $.character_class_escape,
      $._character_escape,
    ),

    class_character: $ => // NOT: \ ] or -
      /[^\\\]\-]/,

    anonymous_capturing_group: $ => seq('(', $.pattern, ')'),

    named_capturing_group: $ => seq('(?<', $.group_name, '>', $.pattern, ')'),

    non_capturing_group: $ => seq('(?:', $.pattern, ')'),

    zero_or_more: quantifierRule($ => '*'),
    one_or_more: quantifierRule($ => '+'),
    optional: quantifierRule($ => '?'),
    count_quantifier: quantifierRule($ => seq(
      '{',
      seq($.decimal_digits, optional(seq(',', $.decimal_digits))),
      '}'
    )),

    backreference_escape: $ => seq('\\k', $.group_name),

    decimal_escape: $ => /\\[1-9][0-9]*/,

    character_class_escape: $ => choice(
      /\\[dDsSwW]/,
      seq(/\\[pP]/, '{', $.unicode_property_value_expression, '}')
    ),

    unicode_property_value_expression: $ => seq(
      optional(seq(alias($.unicode_property, $.unicode_property_name), '=')),
      alias($.unicode_property, $.unicode_property_value)
    ),

    unicode_property: $ => /[a-zA-Z_0-9]+/,

    _character_escape: $ => choice(
      $.control_escape,
      $.control_letter_escape,
      $.identity_escape
    ),

    // TODO: We should technically not accept \0 unless the
    // lookahead is not also a digit.
    // I think this has little bearing on the highlighting of
    // correct regexes.
    control_escape: $ => /\\[bfnrtv0]/,

    control_letter_escape: $ => /\\c[a-zA-Z]/,

    identity_escape: $ => token(seq('\\', /[^kdDsSpPwWbfnrtv0-9]/)),

    // TODO: This is an approximation of RegExpIdentifierName in the
    // formal grammar, which allows for Unicode names through
    // the following mechanism:
    //
    // RegExpIdentifierName[U]::
    //   RegExpIdentifierStart[?U]
    //   RegExpIdentifierName[?U]RegExpIdentifierPart[?U]
    //
    // RegExpIdentifierStart[U]::
    //   UnicodeIDStart
    //   $
    //   _
    //   \RegExpUnicodeEscapeSequence[?U]
    //
    // RegExpIdentifierPart[U]::
    //   UnicodeIDContinue
    //   $
    //   \RegExpUnicodeEscapeSequence[?U]
    //   <ZWNJ> <ZWJ>
    // RegExpUnicodeEscapeSequence[U]::
    //   [+U]uLeadSurrogate\uTrailSurrogate
    //   [+U]uLeadSurrogate
    //   [+U]uTrailSurrogate
    //   [+U]uNonSurrogate
    //   [~U]uHex4Digits
    //   [+U]u{CodePoint}
    group_name: $ => /[A-Za-z0-9]+/,

    decimal_digits: $ => /\d+/
  }
})
