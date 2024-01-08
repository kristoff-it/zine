const PREC = [
  'afunc',
  'pair',
  'conditional',
  'arrow',
  'lazy_or',
  'lazy_and',
  'comparison',
  'pipe_left',
  'pipe_right',
  'colon',
  'plus',
  'times',
  'rational',
  'bitshift',
  'where',
  'prefix',
  'postfix',
  'power',
  'decl',
  'call',
  'dot',
].reduce((result, name, index) => {
  result[name] = index + 10;
  return result;
}, {});

PREC.array = -1;
PREC.tuple = -1; // Bare tuples
PREC.assign = -2;
PREC.stmt = -3;
PREC.macro_arg = -4;

const OPERATORS = {
  assignment: `
    += -= *= /= //= \\= ^= %= <<= >>= >>>= |= &=
    −= ÷= ⊻= ≔ ⩴ ≕
  `,

  arrow: `
    <-- --> <-->
    ← → ↔ ↚ ↛ ↞ ↠ ↢ ↣ ↦ ↤ ↮ ⇎ ⇍ ⇏ ⇐ ⇒ ⇔ ⇴ ⇶ ⇷ ⇸ ⇹ ⇺ ⇻ ⇼ ⇽ ⇾ ⇿ ⟵ ⟶ ⟷ ⟹ ⟺ ⟻ ⟼ ⟽ ⟾ ⟿
    ⤀ ⤁ ⤂ ⤃ ⤄ ⤅ ⤆ ⤇ ⤌ ⤍ ⤎ ⤏ ⤐ ⤑ ⤔ ⤕ ⤖ ⤗ ⤘ ⤝ ⤞ ⤟ ⤠ ⥄ ⥅ ⥆ ⥇ ⥈ ⥊ ⥋ ⥎ ⥐ ⥒ ⥓ ⥖ ⥗ ⥚ ⥛ ⥞
    ⥟ ⥢ ⥤ ⥦ ⥧ ⥨ ⥩ ⥪ ⥫ ⥬ ⥭ ⥰ ⧴ ⬱ ⬰ ⬲ ⬳ ⬴ ⬵ ⬶ ⬷ ⬸ ⬹ ⬺ ⬻ ⬼ ⬽ ⬾ ⬿ ⭀ ⭁ ⭂ ⭃ ⥷ ⭄ ⥺ ⭇ ⭈ ⭉
    ⭊ ⭋ ⭌ ￩ ￫ ⇜ ⇝ ↜ ↝ ↩ ↪ ↫ ↬ ↼ ↽ ⇀ ⇁ ⇄ ⇆ ⇇ ⇉ ⇋ ⇌ ⇚ ⇛ ⇠ ⇢ ↷ ↶ ↺ ↻
  `,

  comparison: `
    > < >= <= == === != !==
    ≥ ≤ ≡ ≠ ≢ ∈ ∉ ∋ ∌ ⊆ ⊈ ⊂ ⊄ ⊊ ∝ ∊ ∍ ∥ ∦ ∷ ∺ ∻ ∽ ∾ ≁ ≃ ≂ ≄ ≅ ≆ ≇ ≈ ≉ ≊ ≋ ≌ ≍ ≎ ≐
    ≑ ≒ ≓ ≖ ≗ ≘ ≙ ≚ ≛ ≜ ≝ ≞ ≟ ≣ ≦ ≧ ≨ ≩ ≪ ≫ ≬ ≭ ≮ ≯ ≰ ≱ ≲ ≳ ≴ ≵ ≶ ≷ ≸ ≹ ≺ ≻ ≼ ≽ ≾
    ≿ ⊀ ⊁ ⊃ ⊅ ⊇ ⊉ ⊋ ⊏ ⊐ ⊑ ⊒ ⊜ ⊩ ⊬ ⊮ ⊰ ⊱ ⊲ ⊳ ⊴ ⊵ ⊶ ⊷ ⋍ ⋐ ⋑ ⋕ ⋖ ⋗ ⋘ ⋙ ⋚ ⋛ ⋜ ⋝ ⋞ ⋟ ⋠
    ⋡ ⋢ ⋣ ⋤ ⋥ ⋦ ⋧ ⋨ ⋩ ⋪ ⋫ ⋬ ⋭ ⋲ ⋳ ⋴ ⋵ ⋶ ⋷ ⋸ ⋹ ⋺ ⋻ ⋼ ⋽ ⋾ ⋿ ⟈ ⟉ ⟒ ⦷ ⧀ ⧁ ⧡ ⧣ ⧤ ⧥ ⩦ ⩧
    ⩪ ⩫ ⩬ ⩭ ⩮ ⩯ ⩰ ⩱ ⩲ ⩳ ⩵ ⩶ ⩷ ⩸ ⩹ ⩺ ⩻ ⩼ ⩽ ⩾ ⩿ ⪀ ⪁ ⪂ ⪃ ⪄ ⪅ ⪆ ⪇ ⪈ ⪉ ⪊ ⪋ ⪌ ⪍ ⪎ ⪏ ⪐ ⪑
    ⪒ ⪓ ⪔ ⪕ ⪖ ⪗ ⪘ ⪙ ⪚ ⪛ ⪜ ⪝ ⪞ ⪟ ⪠ ⪡ ⪢ ⪣ ⪤ ⪥ ⪦ ⪧ ⪨ ⪩ ⪪ ⪫ ⪬ ⪭ ⪮ ⪯ ⪰ ⪱ ⪲ ⪳ ⪴ ⪵ ⪶ ⪷ ⪸
    ⪹ ⪺ ⪻ ⪼ ⪽ ⪾ ⪿ ⫀ ⫁ ⫂ ⫃ ⫄ ⫅ ⫆ ⫇ ⫈ ⫉ ⫊ ⫋ ⫌ ⫍ ⫎ ⫏ ⫐ ⫑ ⫒ ⫓ ⫔ ⫕ ⫖ ⫗ ⫘ ⫙ ⫷ ⫸ ⫹ ⫺ ⊢ ⊣
    ⟂ ⫪ ⫫
  `,

  ellipsis: '… ⁝ ⋮ ⋱ ⋰ ⋯',

  plus: `
    ++ |
    − ¦ ⊕ ⊖ ⊞ ⊟ ∪ ∨ ⊔ ± ∓ ∔ ∸ ≏ ⊎ ⊻ ⊽ ⋎ ⋓ ⟇ ⧺ ⧻ ⨈ ⨢ ⨣ ⨤ ⨥ ⨦ ⨧ ⨨ ⨩ ⨪ ⨫ ⨬ ⨭ ⨮ ⨹ ⨺ ⩁
    ⩂ ⩅ ⩊ ⩌ ⩏ ⩐ ⩒ ⩔ ⩖ ⩗ ⩛ ⩝ ⩡ ⩢ ⩣
  `,

  times: `
    * / % & \\
    ⌿ ÷ · · ⋅ ∘ × ∩ ∧ ⊗ ⊘ ⊙ ⊚ ⊛ ⊠ ⊡ ⊓ ∗ ∙ ∤ ⅋ ≀ ⊼ ⋄ ⋆ ⋇ ⋉ ⋊ ⋋ ⋌ ⋏ ⋒ ⟑ ⦸ ⦼ ⦾ ⦿ ⧶ ⧷
    ⨇ ⨰ ⨱ ⨲ ⨳ ⨴ ⨵ ⨶ ⨷ ⨸ ⨻ ⨼ ⨽ ⩀ ⩃ ⩄ ⩋ ⩍ ⩎ ⩑ ⩓ ⩕ ⩘ ⩚ ⩜ ⩞ ⩟ ⩠ ⫛ ⊍ ▷ ⨝ ⟕ ⟖ ⟗ ⨟
  `,

  bitshift: '<< >> >>>',

  power: `
    ^
    ↑ ↓ ⇵ ⟰ ⟱ ⤈ ⤉ ⤊ ⤋ ⤒ ⤓ ⥉ ⥌ ⥍ ⥏ ⥑ ⥔ ⥕ ⥘ ⥙ ⥜ ⥝ ⥠ ⥡ ⥣ ⥥ ⥮ ⥯ ￪ ￬
  `,

  unary: '! ¬ √ ∛ ∜',

  unary_plus: '+ - ± ∓',
};

const ESCAPE_SEQUENCE = token(seq(
  '\\',
  choice(
    /[^uUx0-7]/,
    /[uU][0-9a-fA-F]{1,6}/, // unicode codepoints
    /[0-7]{1,3}/,
    /x[0-9a-fA-F]{2}/,
  )
));

// Keywords that can be quoted. Some still fail depending on the context.
const KEYWORDS = choice(
  'baremodule',
  'module',
  'abstract',
  'primitive',
  'mutable',
  'struct',
  'quote',
  'let',
  'if',
  'else',
  'elseif',
  'try',
  'catch',
  'finally',
  'for',
  'while',
  'break',
  'continue',
  'using',
  'import',
  'const',
  'global',
  'local',
  'end',
);

module.exports = grammar({
  name: 'julia',

  word: $ => $._word_identifier,

  inline: $ => [
    $._terminator,
    $._definition,
    $._statement,
    $._operation,
  ],

  externals: $ => [
    $.block_comment,
    $._immediate_paren,
    $._immediate_bracket,
    $._immediate_brace,

    $._string_start,
    $._command_start,
    $._immediate_string_start,
    $._immediate_command_start,
    $._string_end,
    $._command_end,
    $._string_content,
    $._string_content_no_interp,
  ],

  // The two notable conflicts in the grammar are:
  // - Arrow function parameters vs tuple expressions
  // - Short function definitions vs function calls
  // The femptolisp parser makes no distinction between these, but having the
  // distinction is better because it's easier to keep track of formal parameters.
  conflicts: $ => [
    [$._function_signature, $._quotable],
    [$._function_signature, $._primary_expression],
    [$._function_signature, $.parameter_list, $._quotable],
    [$._function_signature, $._expression],

    [$._quotable, $.named_field, $.optional_parameter],
    [$._quotable, $.named_field],
    [$.optional_parameter, $.named_field],

    [$._quotable, $.typed_parameter],
    [$._quotable, $.slurp_parameter],
    [$._quotable, $.optional_parameter],
    [$._quotable, $.keyword_parameters],

    [$.parameter_list, $._quotable],
    [$.parameter_list, $._primary_expression],
    [$.parameter_list, $.argument_list],

    // // interpolations
    [$._primary_expression, $.typed_parameter],
    [$._primary_expression, $.keyword_parameters],
    [$._primary_expression, $.named_field],

    // Comprehensions with newlines
    [$.matrix_row, $.comprehension_expression],

    [$.juxtaposition_expression, $._number],
    [$.juxtaposition_expression, $._primary_expression], // adjoint
  ],

  supertypes: $ => [
    $._expression,
    $._statement,
    $._definition,
  ],

  extras: $ => [
    /\s/,
    $.line_comment,
    $.block_comment,
  ],

  rules: {
    source_file: $ => optional($._block),

    _block: $ => seq(
      sep1($._terminator, choice(
        $._expression,
        $.assignment,
        $.bare_tuple,
        $.short_function_definition,
      )),
      optional($._terminator)
    ),

    _expression: $ => choice(
      $._definition,
      $._statement,
      $._number,
      $._primary_expression,
      $._operation,
      $.macrocall_expression,
      $.operator,
      prec(-1, alias(':', $.operator)),
      prec(-1, alias('begin', $.identifier)),
    ),

    assignment: $ => prec.right(PREC.assign, seq(
      // LHS
      choice(
        $._quotable,
        // No function calls. Those are parsed as short_function_definition
        $.field_expression,
        $.index_expression,
        $.parametrized_type_expression,
        $.interpolation_expression,
        $.quote_expression,
        $.typed_expression,
        $.operator,

        $.binary_expression,
        $.unary_expression,
        $.bare_tuple
      ),
      alias('=', $.operator),
      choice(
        $._expression,
        $.assignment,
        $.bare_tuple
      )
    )),

    bare_tuple: $ => prec(PREC.tuple, seq(
      $._expression,
      repeat1(prec(PREC.tuple, seq(',', $._expression)))
    )),

    // Definitions

    _definition: $ => choice(
      $.module_definition,
      $.abstract_definition,
      $.primitive_definition,
      $.struct_definition,
      $.function_definition,
      $.macro_definition
    ),

    module_definition: $ => seq(
      choice('module', 'baremodule'),
      field('name', choice($.identifier, $.interpolation_expression)),
      optional($._terminator),
      optional($._block),
      'end'
    ),

    abstract_definition: $ => seq(
      token(seq('abstract', /\s+/, 'type')),
      field('name', choice($.identifier, $.interpolation_expression)),
      optional(seq($._immediate_brace, alias($.curly_expression, $.type_parameter_list))),
      optional($.type_clause),
      'end'
    ),

    primitive_definition: $ => seq(
      token(seq('primitive', /\s+/, 'type')),
      field('name', choice($.identifier, $.interpolation_expression)),
      optional(seq($._immediate_brace, alias($.curly_expression, $.type_parameter_list))),
      optional($.type_clause),
      $.integer_literal,
      'end'
    ),

    struct_definition: $ => seq(
      optional('mutable'),
      'struct',
      field('name', choice($.identifier, $.interpolation_expression)),
      optional(seq($._immediate_brace, alias($.curly_expression, $.type_parameter_list))),
      optional($.type_clause),
      optional($._terminator),
      optional($._block),
      'end'
    ),

    // Just for type definitions
    type_clause: $ => seq(alias('<:', $.operator), $._primary_expression),

    function_definition: $ => seq(
      'function',
      choice(
        seq(
          choice(
            $._function_signature,
            // Anonymous function
            seq(
              field('parameters', $.parameter_list),
              optional(seq('::', field('return_type', $._primary_expression))),
              optional($.where_clause),
            ),
          ),
          optional($._terminator),
          optional($._block),
        ),
        // zero method functions
        field('name', choice(
          $.identifier,
          $.operator,
        )),
      ),
      'end'
    ),

    short_function_definition: $ => prec.right(PREC.assign, seq(
      $._function_signature,
      '=',
      choice(
        $._expression,
        $.assignment,
        $.bare_tuple,
      ),
    )),

    _function_signature: $ => seq(
      field('name', choice(
        $.identifier,
        $.operator,
        $.field_expression,
        parenthesize(choice(
          $.identifier,
          $.operator,
        )),
        parenthesize(alias($.typed_parameter, $.function_object)),
        $.interpolation_expression,
      )),
      optional(seq($._immediate_brace, alias($.curly_expression, $.type_parameter_list))),

      $._immediate_paren,
      field('parameters', $.parameter_list),

      optional(seq('::', field('return_type', $._primary_expression))),
      optional($.where_clause),
    ),

    where_clause: $ => seq('where', $._expression),

    macro_definition: $ => seq(
      'macro',
      field('name', choice(
        $.identifier,
        $.operator,
        $.interpolation_expression,
      )),
      $._immediate_paren,
      field('parameters', $.parameter_list),
      optional($._terminator),
      optional($._block),
      'end'
    ),

    parameter_list: $ => parenthesize(
      sep(',', choice(
        $.identifier,
        $.slurp_parameter,
        $.optional_parameter,
        $.typed_parameter,
        $.tuple_expression,
        $.interpolation_expression,
        alias($._closed_macrocall_expression, $.macrocall_expression),
        $.call_expression, // Gen.jl
      )),
      optional(','),
      optional($.keyword_parameters),
    ),

    keyword_parameters: $ => seq(
      ';',
      sep1(',', choice(
        $.identifier,
        $.slurp_parameter,
        $.optional_parameter,
        $.typed_parameter,
        $.interpolation_expression,
        alias($._closed_macrocall_expression, $.macrocall_expression),
      )),
      optional(','),
    ),

    optional_parameter: $ => seq(
      choice($.identifier, $.typed_parameter, $.tuple_expression),
      '=',
      $._expression
    ),

    slurp_parameter: $ => seq(
      choice($.identifier, $.typed_parameter),
      '...'
    ),

    typed_parameter: $ => seq(
      optional(field('parameter', choice(
        $.identifier,
        $.tuple_expression,
        $.interpolation_expression,
      ))),
      '::',
      field('type', $._primary_expression),
      optional($.where_clause),
    ),

    // Statements

    _statement: $ => choice(
      // block statements:
      $.compound_statement,
      $.quote_statement,
      $.let_statement,
      $.if_statement,
      $.try_statement,
      $.for_statement,
      $.while_statement,
      // simple statements:
      $.break_statement,
      $.continue_statement,
      $.return_statement,
      $.const_statement,
      $.global_statement,
      $.local_statement,
      $.export_statement,
      $.import_statement,
    ),

    compound_statement: $ => seq('begin', optional($._terminator), optional($._block), 'end'),

    quote_statement: $ => seq('quote', optional($._terminator), optional($._block), 'end'),

    let_statement: $ => seq(
      'let',
      sep(',', choice(
        $.identifier,
        alias($.named_field, $.let_binding),
      )),
      $._terminator,
      optional($._block),
      'end'
    ),

    if_statement: $ => seq(
      'if',
      field('condition', $._expression),
      optional($._terminator),
      optional($._block),
      field('alternative', repeat($.elseif_clause)),
      field('alternative', optional($.else_clause)),
      'end'
    ),

    elseif_clause: $ => seq(
      'elseif',
      field('condition', $._expression),
      optional($._terminator),
      optional($._block)
    ),

    else_clause: $ => seq(
      'else',
      optional($._terminator),
      optional($._block)
    ),

    try_statement: $ => seq(
      'try',
      optional($._terminator),
      optional($._block),
      choice(
        seq(
          $.catch_clause,
          optional($.else_clause),
          optional($.finally_clause),
        ),
        seq(
          $.finally_clause,
          optional($.catch_clause),
          // `else` is not valid here.
        ),
      ),
      'end'
    ),

    catch_clause: $ => prec(1, seq(
      'catch',
      optional($.identifier),
      optional($._terminator),
      optional($._block),
    )),

    finally_clause: $ => seq(
      'finally',
      optional($._terminator),
      optional($._block),
    ),

    for_statement: $ => seq(
      'for',
      sep1(',', $.for_binding),
      optional($._terminator),
      optional($._block),
      'end'
    ),

    while_statement: $ => seq(
      'while',
      field('condition', $._expression),
      optional($._terminator),
      optional($._block),
      'end'
    ),

    break_statement: _ => 'break',

    continue_statement: _ => 'continue',

    return_statement: $ => prec.right(PREC.stmt, seq(
      'return',
      optional(choice(
        $._expression,
        $.assignment,
        $.bare_tuple,
      ))
    )),

    const_statement: $ => prec.right(PREC.stmt, seq(
      'const',
      choice(
        $.assignment,
        $.identifier,
        $.typed_expression,
      ),
    )),

    global_statement: $ => prec.right(PREC.stmt, seq(
      'global',
      choice(
        $.assignment,
        $.bare_tuple,
        $.identifier,
        $.typed_expression,
        $.function_definition,
        $.short_function_definition,
      ),
    )),

    local_statement: $ => prec.right(PREC.stmt, seq(
      'local',
      choice(
        $.assignment,
        $.bare_tuple,
        $.identifier,
        $.typed_expression,
        $.function_definition,
        $.short_function_definition,
      ),
    )),


    _exportable: $ => choice(
      $.identifier,
      $.macro_identifier,
      $.operator,
      $.interpolation_expression,
      parenthesize(choice($.identifier, $.operator)),
    ),

    export_statement: $ => seq(
      'export',
      prec.right(sep1(',', $._exportable)),
    ),

    relative_qualifier: $ => seq(
      token(repeat1('.')),
      choice(
        $.identifier,
        $.scoped_identifier,
      )
    ),

    _importable: $ => choice(
      $._exportable,
      $.scoped_identifier,
      $.relative_qualifier,
    ),

    import_alias: $ => seq($._importable, 'as', $.identifier),

    _import_list: $ => prec.right(sep1(',', choice(
      $._importable,
      $.import_alias,
    ))),

    selected_import: $ => seq(
      $._importable,
      token.immediate(':'),
      $._import_list,
    ),

    import_statement: $ => seq(
      choice('import', 'using'),
      choice(
        $._import_list,
        $.selected_import,
      ),
    ),


    // Quotables are expressions that can be quoted without additional parentheses.
    _quotable: $ => choice(
      $._array,
      $.identifier,
      $.curly_expression, // Only valid in macros
      $.parenthesized_expression,
      $.tuple_expression,
      $._string,
    ),

    _array: $ => choice(
      $.comprehension_expression,
      $.matrix_expression,
      $.vector_expression,
    ),

    comprehension_expression: $ => prec(PREC.array, seq(
      '[',
      choice(
        $._expression,
        $.assignment,
      ),
      optional($._terminator),
      $._comprehension_clause,
      ']'
    )),

    _comprehension_clause: $ => seq(
      $.for_clause,
      optional('\n'),
      sep(optional('\n'), choice(
        $.for_clause,
        $.if_clause
      )),
      optional('\n'),
    ),

    if_clause: $ => seq(
      'if',
      $._expression
    ),

    for_clause: $ => prec.right(seq(
      'for',
      sep1(',', $.for_binding)
    )),

    for_binding: $ => seq(
      choice(
        $.identifier,
        $.tuple_expression,
        $.typed_parameter,
        $.interpolation_expression,
      ),
      choice('in', '=', '∈'),
      $._expression
    ),

    matrix_expression: $ => prec(PREC.array, seq(
      '[',
      choice(
        // Must allow newlines even if there's already a semicolon.
        seq($.matrix_row, $._terminator, optional('\n')),
        sep1(seq($._terminator, optional('\n')), $.matrix_row),
      ),
      optional($._terminator),
      optional('\n'),
      ']'
    )),

    matrix_row: $ => repeat1(prec(PREC.array, choice(
      $._expression,
      alias($.named_field, $.assignment), // JuMP.jl
    ))),

    vector_expression: $ => seq(
      '[',
      sep(',', choice(
        $._expression,
        alias($.named_field, $.assignment), // JuMP.jl
      )),
      optional(','),
      ']'
    ),

    parenthesized_expression: $ => parenthesize(
      sep1(';', choice(
        $._expression,
        $.assignment,
        $.short_function_definition,
      )),
      optional($._comprehension_clause),
      optional(';'),
    ),

    tuple_expression: $ => parenthesize(optional(
      choice(
        // Singleton requires comma
        seq(
          choice($._expression, $.named_field),
          ','
        ),
        seq(
          choice($._expression, $.named_field),
          repeat1(seq(',', choice($._expression, $.named_field))),
          optional(choice(
            $._comprehension_clause,
            ',',
          )),
        ),
        ';', // Empty NamedTuple
        // NamedTuple with leading semicolon
        seq(
          ';',
          sep1(',', choice($._expression, $.named_field)),
          optional(','),
        ),
      ),
    )),

    curly_expression: $ => seq(
      '{',
      sep(',', choice(
        $._expression,
        alias($.named_field, $.assignment),
      )),
      optional(','),
      '}'
    ),


    // Primary expressions can be called, indexed, accessed, and type parametrized.
    _primary_expression: $ => choice(
      $._quotable,
      $.adjoint_expression,
      $.broadcast_call_expression,
      $.call_expression,
      alias($._closed_macrocall_expression, $.macrocall_expression),
      $.parametrized_type_expression,
      $.field_expression,
      $.index_expression,
      $.interpolation_expression,
      $.quote_expression,
    ),

    adjoint_expression: $ => prec(PREC.postfix, seq(
      $._primary_expression,
      token.immediate("'"),
    )),

    field_expression: $ => prec(PREC.dot, seq(
      field('value', $._primary_expression),
      token.immediate('.'),
      choice(
        $.identifier,
        $.interpolation_expression,
        $.quote_expression,
        $._string,
      ),
    )),

    index_expression: $ => seq(
      $._primary_expression,
      $._immediate_bracket,
      $._array,
    ),

    parametrized_type_expression: $ => seq(
      $._primary_expression,
      $._immediate_brace,
      $.curly_expression,
    ),

    call_expression: $ => prec(PREC.call, seq(
      choice($._primary_expression, $.operator),
      $._immediate_paren,
      $.argument_list,
      optional($.do_clause)
    )),

    broadcast_call_expression: $ => prec(PREC.call, seq(
      $._primary_expression,
      token.immediate('.'),
      $._immediate_paren,
      $.argument_list,
      optional($.do_clause)
    )),

    _closed_macrocall_expression: $ => prec(PREC.call, seq(
      optional(seq(
        $._primary_expression,
        token.immediate('.'),
      )),
      $.macro_identifier,
      choice(
        seq($._immediate_brace, $.curly_expression),
        seq($._immediate_bracket, $._array),
        seq($._immediate_paren, $.argument_list, optional($.do_clause)),
      ),
    )),

    macrocall_expression: $ => prec.right(seq(
      optional(seq(
        $._primary_expression,
        token.immediate('.'),
      )),
      $.macro_identifier,
      optional($.macro_argument_list),
    )),

    macro_argument_list: $ => prec.left(repeat1(prec(PREC.macro_arg, choice(
      $._expression,
      $.assignment,
      $.bare_tuple,
      $.short_function_definition,
    )))),

    argument_list: $ => parenthesize(
      optional(choice(
        seq(
          sep1(',', choice(
            $._expression,
            alias($.named_field, $.named_argument)
          )),
          optional(seq(
            ',',
            optional(seq($._expression, $._comprehension_clause)),
          )),
        ),
        seq($._expression, $._comprehension_clause),
      )),
      optional(seq(
        ';',
        sep(',', choice(
          $._expression,
          alias($.named_field, $.named_argument),
        )),
      )),
      optional(','),
    ),

    do_clause: $ => seq(
      'do',
      alias($._do_parameter_list, $.parameter_list),
      optional($._block),
      'end'
    ),

    _do_parameter_list: $ => seq(
      sep(',', choice(
        $.identifier,
        $.slurp_parameter,
        $.typed_parameter,
        $.tuple_expression,
        parenthesize(choice(
          $.identifier,
          $.slurp_parameter,
          $.typed_parameter,
        )),
      )),
      $._terminator,
    ),

    named_field: $ => seq(
      choice(
        $.identifier,
        $.interpolation_expression,
      ),
      '=',
      choice(
        $._expression,
        $.named_field,
      ),
    ),

    interpolation_expression: $ => prec.right(PREC.prefix, seq(
      '$',
      choice(
        $._number,
        $._quotable,
      ),
    )),

    quote_expression: $ => prec.right(PREC.prefix, seq(
      ':',
      choice(
        $._number,
        $._string,
        $.identifier,
        $.operator,
        seq($._immediate_brace, $.curly_expression),
        seq($._immediate_bracket, $._array),
        seq($._immediate_paren, choice(
          $.parenthesized_expression,
          $.tuple_expression,
          // Syntactic operators in parentheses
          parenthesize(
            alias(
              choice(
                '::', ':=', '.=', '=',
                $._assignment_operator,
                $._lazy_or_operator,
                $._lazy_and_operator,
                $._syntactic_operator,
              ),
              $.operator,
            ),
          ),
        )),
        // Syntactic operators without parentheses
        alias(
          choice(
            $._assignment_operator,
            $._lazy_or_operator,
            $._lazy_and_operator,
            $._syntactic_operator,
          ),
          $.operator,
        ),
        alias(token.immediate(KEYWORDS), $.identifier),
      ),
    )),

    // Operations

    _operation: $ => choice(
      // Use regular operators
      $.unary_expression,
      $.binary_expression,
      $.range_expression,
      // Use syntactic operators
      $.splat_expression,
      $.ternary_expression,
      $.typed_expression,
      $.function_expression,
      // Other stuff
      $.juxtaposition_expression,
      $.compound_assignment_expression,
      $.where_expression,
    ),

    binary_expression: $ => {
      const table = [
        [prec.right, PREC.pair, $._pair_operator],
        [prec.right, PREC.arrow, $._arrow_operator],
        [prec.left, PREC.lazy_or, $._lazy_or_operator],
        [prec.left, PREC.lazy_and, $._lazy_and_operator],
        [prec.left, PREC.comparison, choice('in', 'isa', $._comparison_operator, $._type_order_operator)],
        [prec.right, PREC.pipe_left, $._pipe_left_operator],
        [prec.left, PREC.pipe_right, $._pipe_right_operator],
        [prec.left, PREC.colon, $._ellipsis_operator],
        [prec.left, PREC.plus, choice($._unary_plus_operator, $._plus_operator)],
        [prec.left, PREC.times, $._times_operator],
        [prec.left, PREC.rational, $._rational_operator],
        [prec.left, PREC.bitshift, $._bitshift_operator],
        [prec.left, PREC.power, $._power_operator],
      ];

      return choice(...table.map(([fn, prec, op]) => fn(prec, seq(
        $._expression,
        alias(op, $.operator),
        $._expression,
      ))));
    },

    unary_expression: $ => prec.right(PREC.prefix, seq(
      alias(choice(
        $._tilde_operator,
        $._type_order_operator,
        $._unary_operator,
        $._unary_plus_operator,
      ), $.operator),
      $._expression,
    )),

    range_expression: $ => prec.left(PREC.colon, seq(
      $._expression,
      token.immediate(':'),
      $._expression
    )),

    splat_expression: $ => prec(PREC.colon, seq($._expression, '...')),

    ternary_expression: $ => prec.right(PREC.conditional, seq(
      $._expression,
      '?',
      choice(
        $._expression,
        $.assignment,
      ),
      ':',
      choice(
        $._expression,
        $.assignment,
      ),
    )),

    typed_expression: $ => prec(PREC.decl, seq(
      $._expression,
      '::',
      choice($._primary_expression)
    )),

    function_expression: $ => prec.right(PREC.afunc, seq(
      choice(
        $.identifier,
        $.parameter_list,
        alias($.typed_expression, $.typed_parameter),
      ),
      '->',
      choice(
        $._expression,
        $.assignment,
      )
    )),

    juxtaposition_expression: $ => prec.left(seq(
      choice(
        $.integer_literal,
        $.float_literal,
        $.adjoint_expression,
      ),
      $._primary_expression,
    )),

    compound_assignment_expression: $ => prec.right(PREC.assign, seq(
      $._primary_expression,
      alias(choice($._assignment_operator, $._tilde_operator), $.operator),
      $._expression,
    )),

    where_expression: $ => prec.left(PREC.where, seq(
      $._expression,
      'where',
      $._expression,
    )),



    // Tokens

    macro_identifier: $ => seq('@', choice(
      $.identifier,
      $.scoped_identifier,
      $.operator,
      alias($._syntactic_operator, $.operator),
    )),

    scoped_identifier: $ => seq(
      choice($.identifier, $.scoped_identifier),
      token.immediate('.'),
      choice(
        $.identifier,
        $.interpolation_expression,
        $.quote_expression,
      ),
    ),

    _word_identifier: _ => {
      const nonIdentifierCharacters = [
        '#',
        '$',
        ',',
        ':',
        ';',
        '@',
        '~',
        '(', ')',
        '{', '}',
        ...Object.values(OPERATORS),
      ].join(' ')
        .trim()
        .replace(/!/g, '')
        .replace(/-/g, '')
        .replace(/\\/g, '\\\\')
        .replace(/\s+/g, '');

      // Some symbols in Sm and So unicode categories that are identifiers
      const validMathSymbols = "°∀-∇∎-∑∫-∳";

      const start = `[_\\p{XID_Start}${validMathSymbols}\\p{Emoji}&&[^0-9#*]]`;
      const rest = `[^"'\`\\s\\.\\-\\[\\]${nonIdentifierCharacters }]*`;
      return new RegExp(start + rest);
    },

    identifier: $ => $._word_identifier,

    // Literals

    _number: $ => choice(
      $.boolean_literal,
      $.integer_literal,
      $.float_literal,
    ),

    boolean_literal: _ => choice('true', 'false'),

    integer_literal: _ => choice(
      token(seq('0b', numeral('01'))),
      token(seq('0o', numeral('0-7'))),
      token(seq('0x', numeral('0-9a-fA-F'))),
      numeral('0-9'),
    ),

    float_literal: _ => {
      const dec = numeral('0-9');
      const hex = numeral('0-9a-fA-F');
      const exponent = /[eEf][+-]?\d+/;
      const hex_exponent = /p[+-]?\d+/;

      const leading_period = token(seq(
        '.',
        dec,
        optional(exponent),
      ));

      // This has to be split into two tokens to avoid conflicts with ellipsis
      const trailing_period = seq(
        dec,
        token.immediate(seq(
          '.',
          optional(dec),
          optional(exponent),
        )),
      );

      const just_exponent = token(seq(dec, exponent));

      const hex_float = token(seq(
        choice(
          seq('0x', hex, optional('.'), optional(hex)),
          seq('0x.', hex),
        ),
        hex_exponent,
      ));

      return choice(leading_period, trailing_period, just_exponent, hex_float);
    },

    _string: $ => choice(
      $.character_literal,
      $.string_literal,
      $.command_literal,
      $.prefixed_string_literal,
      $.prefixed_command_literal,
    ),

    escape_sequence: _ => ESCAPE_SEQUENCE,

    character_literal: _ => token(seq(
      "'",
      choice(
        /[^'\\]/,
        ESCAPE_SEQUENCE,
      ),
      "'"
    )),

    string_literal: $ => seq(
      $._string_start,
      repeat(choice($._string_content, $.string_interpolation, $.escape_sequence)),
      $._string_end,
    ),

    command_literal: $ => seq(
      $._command_start,
      repeat(choice($._string_content, $.string_interpolation, $.escape_sequence)),
      $._command_end,
    ),

    prefixed_string_literal: $ => prec.left(seq(
      field('prefix', $.identifier),
      $._immediate_string_start,
      repeat(choice($._string_content_no_interp, $.escape_sequence)),
      $._string_end,
      optional(field('suffix', $.identifier)),
    )),

    prefixed_command_literal: $ => prec.left(seq(
      field('prefix', $.identifier),
      $._immediate_command_start,
      repeat(choice($._string_content_no_interp, $.escape_sequence)),
      $._command_end,
      optional(field('suffix', $.identifier)),
    )),

    string_interpolation: $ => seq(
      '$',
      choice(
        $.identifier,
        seq($._immediate_paren, parenthesize(choice(
          $._expression,
          alias($.named_field, $.assignment),
        ))),
      ),
    ),

    operator: $ => choice(
      // NOTE: Syntactic operators (&&, +=, etc) cannot be used as identifiers.
      $._pair_operator,
      $._arrow_operator,
      $._comparison_operator,
      $._pipe_left_operator,
      $._pipe_right_operator,
      $._ellipsis_operator,
      $._plus_operator,
      $._times_operator,
      $._rational_operator,
      $._bitshift_operator,
      $._power_operator,
      $._tilde_operator,
      $._type_order_operator,
      $._unary_operator,
      $._unary_plus_operator,
    ),

    _assignment_operator: _ => token(choice(':=', '$=', '.=', addDots(OPERATORS.assignment))),

    _pair_operator: _ => token(addDots('=>')),

    _arrow_operator: _ => token(addDots(OPERATORS.arrow)),

    _lazy_or_operator: _ => token(addDots('||')),

    _lazy_and_operator: _ => token(addDots('&&')),

    _comparison_operator: _ => token(addDots(OPERATORS.comparison)),

    _pipe_right_operator: _ => token(addDots('|>')),

    _pipe_left_operator: _ => token(addDots('<|')),

    _ellipsis_operator: _ => token(choice('..', addDots(OPERATORS.ellipsis))),

    _plus_operator: _ => token(addDots(OPERATORS.plus)),

    _times_operator: _ => token(addDots(OPERATORS.times)),

    _rational_operator: _ => token(addDots('//')),

    _bitshift_operator: _ => token(addDots(OPERATORS.bitshift)),

    _power_operator: _ => token(addDots(OPERATORS.power)),


    _tilde_operator: _ => token(addDots('~')), // unary or assignment

    _type_order_operator: _ => token(addDots('<: >:')), // unary or comparison

    _unary_operator: _ => token(addDots(OPERATORS.unary)),

    _unary_plus_operator: _ => token(addDots(OPERATORS.unary_plus)),


    _syntactic_operator: _ => token(choice('$', '.', '...', '->', '?')),


    _terminator: _ => choice('\n', /;+/),

    line_comment: _ => token(seq('#', /.*/))
  }
});

function sep(separator, rule) {
  return optional(sep1(separator, rule));
}

function sep1(separator, rule) {
  return seq(rule, repeat(seq(separator, rule)));
}

function addDots(operatorString) {
  const operators = operatorString.trim().split(/\s+/);
  return seq(optional('.'), choice(...operators));
}

function numeral(range) {
  return RegExp(`[${range}]|([${range}][${range}_]*[${range}])`);
}

function parenthesize(...rules) {
  return seq('(', ...rules, ')');
}
