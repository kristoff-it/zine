module.exports = grammar({
  name: 'tsq',

  extras: $ => [/\s/, $.comment],
  word: $ => $._identifier,

  rules: {
    query: $ => repeat(choice($.pattern, $.predicate)),
    pattern: $ => $._pattern,

    comment: $ => token(seq(';', /.*/)),

    _pattern: $ => seq(
      field('pattern', choice(
        $.alternation,
        $.anonymous_leaf,
        $.group,
        $.named_node,
        $.wildcard_node,
      )),
      optional(field('quantifier', $._quantifier)),
      optional($.capture),
    ),

    _quantifier: $ => choice(
      $.one_or_more,
      $.zero_or_one,
      $.zero_or_more,
    ),
    one_or_more: $ => '+',
    zero_or_one: $ => '?',
    zero_or_more: $ => '*',

    capture: $ => /@[a-zA-Z0-9_-][a-zA-Z0-9.?!_-]*/,

    alternation: $ => seq('[', repeat1(choice($.choice, $.predicate)), ']'),
    choice: $ => $._pattern,

    anonymous_leaf: $ => $._string,

    _string: $ => seq(
      '"',
      repeat(choice(
        token.immediate(prec(1, /[^"\n\\]+/)),
        $.escape_sequence
      )),
      '"',
    ),

    escape_sequence: $ => token.immediate(seq(
      '\\',
      choice('n', 'r', 't', '0', '\\'),
    )),

    _identifier: $ => /[a-zA-Z0-9_-][a-zA-Z0-9.?!_-]*/,

    group: $ => seq('(', repeat1(choice($.pattern, $.predicate)), ')'),

    named_node: $ => seq(
      '(',
      $.node_name,
      optional(seq(
        repeat1(seq(
          optional($.anchor),
          choice($.child, $.negated_child, $.predicate),
        )),
        optional($.anchor),
      )),
      ')',
    ),

    node_name: $ => $._identifier,

    anchor: $ => '.',

    child: $ => seq(
      optional(seq($.field_name, ':')),
      $._pattern,
    ),

    field_name: $ => $._identifier,

    negated_child: $ => seq('!', $.field_name),

    predicate: $ => seq(
      '(',
      $.predicate_name,
      repeat(choice($.capture, $.string)),
      ')',
    ),

    predicate_name: $ => /#[a-zA-Z0-9_-][a-zA-Z0-9.?!_-]*/,
    string: $ => $._string,

    wildcard_node: $ => prec.right(choice('_', seq('(', '_', ')'))),
  }
});
