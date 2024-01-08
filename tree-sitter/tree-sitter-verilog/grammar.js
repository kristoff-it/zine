/* eslint-disable arrow-parens */
/* eslint-disable camelcase */
/* eslint-disable-next-line spaced-comment */
/* eslint-disable-no-undef */
/* eslint-disable-no-unused-vars */
/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

'use strict';

const PREC = {

  PARENT: 37,     // () [] :: .                                   Left Highest
  UNARY: 36,      // + - ! ~ & ~& | ~| ^ ~^ ^~ ++ -- (unary)
  POW: 35,        // **                                           Left
  MUL: 34,        // * / %                                        Left
  ADD: 33,        // + - (binary)                                 Left
  SHIFT: 32,      // << >> <<< >>>                                Left
  RELATIONAL: 31, // < <= > >= inside dist                        Left
  EQUAL: 30,      // == != === !== ==? !=?                        Left
  AND: 29,        // & (binary)                                   Left
  XOR: 28,        // ^ ~^ ^~ (binary)                             Left
  OR: 27,         // | (binary)                                   Left

  // The matches operator shall have higher precedence than the && and || operators
  MATCHES: 26,

  LOGICAL_AND: 25, // &&                                           Left
  LOGICAL_OR: 24, // ||                                           Left
  CONDITIONAL: 23, // ?: (conditional operator)                    Right
  IMPLICATION: 22, // –> <–>                                       Right
  ASSIGN: 21,     // = += -= *= /= %= &= ^= |= <<= >>= <<<= >>>= := :/ <= None
  CONCAT: 20,     // {} {{}}                            Concatenation   Lowest

  SPARENT: 19,    // [* ] [= ] [-> ]
  SHARP2: 18,     // ##                                                 Left
  throughout: 17, // throughout                                         Right
  within: 16,     // within                                             Left
  intersect: 15,  // intersect                                          Left
  nexttime: 14,   // not, nexttime, s_nexttime
  and: 13,        // and                                                Left
  or: 12,         // or                                                 Left
  iff: 11,        // iff                                                Right
  until: 10,      // until, s_until, until_with, s_until_with, implies  Right
  INCIDENCE: 9,   // |->, |=>, #-#, #=#                                 Right
  always: 8       // always, s_always, eventually, s_eventually,        —
  // if-else, case , accept_on, reject_on,
  // sync_accept_on, sync_reject_on
};

/**
 *
 * @param {(Rule|string|RegExp)[]} rules
 *
 * @return {ChoiceRule}
 *
 */
function optseq(...rules) {
  return optional(prec.left(seq(...rules)));
}

/**
 *
 * @param {(Rule|string|RegExp)[]} rules
 *
 * @return {RepeatRule}
 *
 */
function repseq(...rules) {
  return repeat(prec.left(seq(...rules)));
}

/**
 * Creates a rule to match one or more of the rules separated by the separator
 *
 * @param {string} separator - The separator to use.
 * @param {Rule} rule
 *
 * @return {PrecLeftRule}
 *
 */
function sep1(separator, rule) {
  return prec.left(seq(
    rule,
    repeat(prec.left(seq(separator, rule)))
  ));
}

/**
 *
 * @param {number} precedence
 * @param {string} separator
 * @param {Rule} rule
 *
 * @returns {PrecLeftRule}
 *
 */
function psep1(precedence, separator, rule) {
  return prec.left(precedence, seq(
    rule,
    repeat(prec.left(seq(separator, rule)))
  ));
}

/**
 *
 * @param {GrammarSymbols<string>} $
 * @param {number} prior
 * @param {Rule|string} ops
 *
 * @returns {PrecLeftRule}
 *
 */
function exprOp($, prior, ops) {
  return prec.left(prior, seq($.expression, ops, repeat($.attribute_instance), $.expression));
}

/**
 *
 * @param {GrammarSymbols<string>} $
 * @param {number} prior
 * @param {Rule|string} ops
 *
 * @returns {PrecLeftRule}
 *
 */
function constExprOp($, prior, ops) {
  return prec.left(prior, seq($.constant_expression, ops, repeat($.attribute_instance), $.constant_expression));
}

/**
 *
 * @param {string} command 
 *
 * @returns {AliasRule}
 *
 */
function directive(command) {
  return alias(new RegExp('`' + command), 'directive_' + command);
}

/*
    Verilog parser grammar based on IEEE Std 1800-2017.
*/

const rules = {
  source_file: $ => repeat($._description),

  /* 22. Compiler directives */

  /* 22-1 `include */

  double_quoted_string: $ => seq(
    '"', token.immediate(prec(1, /[^\\"\n]+/)), '"'
  ),

  include_compiler_directive_standard: $ => seq(
    '<', token.immediate(prec(1, /[^\\>\n]+/)), '>'
  ),

  include_compiler_directive: $ => seq(
    directive('include'),
    choice(
      $.double_quoted_string,
      $.include_compiler_directive_standard
    )
  ),

  /* 22-2 `define */

  default_text: $ => /\w+/,

  macro_text: $ => /(\\(.|\r?\n)|[^\\\n])*/,

  text_macro_name: $ => seq(
    $.text_macro_identifier,
    optseq('(', $.list_of_formal_arguments, ')')
  ),

  list_of_formal_arguments: $ => sep1(',', $.formal_argument),

  formal_argument: $ => seq(
    $.simple_identifier,
    optseq('=', $.default_text)
  ),

  text_macro_identifier: $ => $._identifier,

  /* 22-5 define */

  text_macro_definition: $ => seq(
    directive('define'),
    $.text_macro_name,
    optional($.macro_text),
    '\n'
  ),

  /* 22-3 usage */

  text_macro_usage: $ => seq(
    '`',
    $.text_macro_identifier,
    optseq('(', $.list_of_actual_arguments, ')')
  ),

  simple_text_macro_usage: $ => seq(
    '`',
    $.text_macro_identifier
  ),

  /* 22-4 22-5 */

  id_directive: $ => seq(
    choice(
      directive('ifdef'),
      directive('ifndef'),
      directive('elsif'),
      directive('undef') /* 22-5-2 */
    ),
    $.text_macro_identifier
  ),

  zero_directive: $ => choice(
    directive('resetall'), /* 22-3 */
    directive('undefineall'), /* 22-5-3 */
    directive('endif'),
    directive('else'),
    directive('nounconnected_drive'),
    directive('celldefine'), /* 22-10 */
    directive('endcelldefine'),
    directive('end_keywords') /* 22.14 */
  ),

  /* 22-7 timescale */

  timescale_compiler_directive: $ => seq(
    directive('timescale'),
    $.time_literal, // time_unit,
    '/',
    $.time_literal, // time_precision
    '\n'
  ),

  /* 22-8 default_nettype */

  default_nettype_compiler_directive: $ => seq(
    directive('default_nettype'),
    $.default_nettype_value,
    '\n'
  ),

  default_nettype_value: $ => choice('wire', 'tri', 'tri0', 'tri1', 'wand', 'triand', 'wor', 'trior', 'trireg', 'uwire', 'none'),

  /* 22-9 */

  unconnected_drive: $ => seq(
    directive('unconnected_drive'),
    choice('pull0', 'pull1'),
    '\n'
  ),

  /* 22-12 */

  line_compiler_directive: $ => seq(
    directive('line'),
    $.unsigned_number,
    $.double_quoted_string,
    $.unsigned_number,
    '\n'
  ),

  /* 22.13 */
  /* `__FILE__ and `__LINE__ */

  /* 22.14 */
  begin_keywords: $ => seq(
    directive('begin_keywords'),
    $.double_quoted_string
  ),

  _directives: $ => choice(
    $.line_compiler_directive,
    $.include_compiler_directive,
    $.text_macro_definition,
    $.text_macro_usage,
    $.id_directive,
    $.zero_directive,
    $.timescale_compiler_directive,
    $.default_nettype_compiler_directive,
    $.unconnected_drive,
    $.begin_keywords
  ),

  // TODO missing arguments, empty list of arguments

  list_of_actual_arguments: $ => sep1(',', $._actual_argument),

  _actual_argument: $ => $.expression,

  /* A.1.1 Library source text */

  // library_text: $ => repeat($.library_description),

  // library_description: $ => choice(
  //   $.library_declaration,
  //   $.include_statement,
  //   $.config_declaration,
  //   ';'
  // ),
  //
  // library_declaration: $ => seq(
  //   'library',
  //   $.library_identifier,
  //   sep1(',', $.file_path_spec),
  //   optseq('-incdir', sep1(',', $.file_path_spec)),
  //   ';'
  // ),
  //
  // include_statement: $ => seq('include', $.file_path_spec, ';'),

  /* A.1.2 SystemVerilog source text */

  _description: $ => choice(
    $._directives,
    $.module_declaration,
    $.udp_declaration,
    $.interface_declaration,
    $.program_declaration,
    $.package_declaration,
    seq(repeat($.attribute_instance), $._package_item),
    seq(repeat($.attribute_instance), $.bind_directive)
    // $.config_declaration,
  ),

  // module_nonansi_header: $ =>
  //   { attribute_instance } module_keyword [ lifetime ] _module_identifier
  //     { package_import_declaration } [ parameter_port_list ] list_of_ports ';'
  //
  // module_ansi_header: $ =>
  //   { attribute_instance } module_keyword [ lifetime ] _module_identifier
  //     { package_import_declaration } [ parameter_port_list ] [ list_of_port_declarations ] ';'
  //
  // module_declaration: $ =>
  //   module_nonansi_header [ timeunits_declaration ] { module_item }
  //     'endmodule' [ ':' _module_identifier ]
  // | module_ansi_header [ timeunits_declaration ] { non_port_module_item }
  //     'endmodule' [ ':' _module_identifier ]
  // | { attribute_instance } module_keyword [ lifetime ] _module_identifier '(' '.*' ')' ';'
  //   [ timeunits_declaration ] { module_item } 'endmodule' [ ':' _module_identifier ]
  // | 'extern' module_nonansi_header
  // | 'extern' module_ansi_header

  module_header: $ => seq(
    repeat($.attribute_instance),
    $.module_keyword,
    optional($.lifetime),
    $._module_identifier
  ),

  module_nonansi_header: $ => seq(
    repeat($.package_import_declaration),
    optional($.parameter_port_list),
    $.list_of_ports
  ),

  module_ansi_header: $ => seq(
    repeat($.package_import_declaration),
    choice(
      seq($.parameter_port_list, optional($.list_of_port_declarations)),
      $.list_of_port_declarations
    )
  ),

  module_declaration: $ => choice(
    seq(
      $.module_header,
      optional(choice(
        $.module_nonansi_header,
        $.module_ansi_header,
        seq('(', '.*', ')')
      )),
      ';',
      optional($.timeunits_declaration),
      repeat($._module_item),
      'endmodule', optseq(':', $._module_identifier)
    ),
    seq('extern', $.module_header, choice(
      $.module_nonansi_header,
      $.module_ansi_header
    ))
  ),

  module_keyword: $ => choice('module', 'macromodule'),

  interface_declaration: $ => choice(
    seq(
      $.interface_nonansi_header,
      optional($.timeunits_declaration),
      repeat($.interface_item),
      'endinterface', optseq(':', $.interface_identifier)
    ),
    seq(
      $.interface_ansi_header,
      optional($.timeunits_declaration),
      repeat($._non_port_interface_item),
      'endinterface', optseq(':', $.interface_identifier)
    ),
    seq(
      repeat($.attribute_instance),
      'interface',
      $.interface_identifier,
      '(', '.*', ')', ';',
      optional($.timeunits_declaration),
      repeat($.interface_item),
      'endinterface', optseq(':', $.interface_identifier)
    ),
    seq('extern', $.interface_nonansi_header),
    seq('extern', $.interface_ansi_header)
  ),

  interface_nonansi_header: $ => seq(
    repeat($.attribute_instance),
    'interface',
    optional($.lifetime),
    $.interface_identifier,
    repeat($.package_import_declaration),
    optional($.parameter_port_list),
    $.list_of_ports,
    ';'
  ),

  interface_ansi_header: $ => seq(
    repeat($.attribute_instance),
    'interface',
    optional($.lifetime),
    $.interface_identifier,
    repeat($.package_import_declaration),
    optional($.parameter_port_list),
    optional($.list_of_port_declarations),
    ';'
  ),

  program_declaration: $ => choice(
    seq(
      $.program_nonansi_header,
      optional($.timeunits_declaration),
      repeat($.program_item),
      'endprogram', optseq(':', $.program_identifier)
    ),
    seq(
      $.program_ansi_header,
      optional($.timeunits_declaration),
      repeat($.non_port_program_item),
      'endprogram', optseq(':', $.program_identifier)
    ),
    seq(
      repeat($.attribute_instance),
      'program',
      $.program_identifier,
      '(', '.*', ')', ';',
      optional($.timeunits_declaration),
      repeat($.program_item),
      'endprogram', optseq(':', $.program_identifier)
    ),
    seq('extern', $.program_nonansi_header),
    seq('extern', $.program_ansi_header)
  ),

  program_nonansi_header: $ => seq(
    repeat($.attribute_instance),
    'program',
    optional($.lifetime),
    $.program_identifier,
    repeat($.package_import_declaration),
    optional($.parameter_port_list),
    $.list_of_ports,
    ';'
  ),

  program_ansi_header: $ => seq(
    repeat($.attribute_instance),
    'program',
    optional($.lifetime),
    $.program_identifier,
    repeat($.package_import_declaration),
    optional($.parameter_port_list),
    optional($.list_of_port_declarations),
    ';'
  ),

  checker_declaration: $ => seq(
    'checker',
    $.checker_identifier,
    optseq('(', optional($.checker_port_list), ')'),
    ';',
    repseq(
      repeat($.attribute_instance),
      $._checker_or_generate_item
    ),
    'endchecker', optseq(':', $.checker_identifier)
  ),

  class_declaration: $ => seq(
    optional('virtual'),
    'class',
    optional($.lifetime),
    $.class_identifier,
    optional($.parameter_port_list),
    optseq(
      'extends', $.class_type, optional($.list_of_arguments_parent)
    ),
    optseq(
      'implements', sep1(',', $.interface_class_type)
    ),
    ';',
    repeat($.class_item),
    'endclass', optseq(':', $.class_identifier)
  ),

  interface_class_type: $ => seq(
    $.ps_class_identifier,
    optional($.parameter_value_assignment)
  ),

  interface_class_declaration: $ => seq(
    'interface', 'class',
    $.class_identifier,
    optional($.parameter_port_list),
    optseq(
      'extends', optional(sep1(',', $.interface_class_type)), ';'
    ),
    repeat($.interface_class_item),
    'endclass', optseq(':', $.class_identifier)
  ),

  interface_class_item: $ => choice(
    $.type_declaration,
    seq(repeat($.attribute_instance), $.interface_class_method),
    seq($._any_parameter_declaration, ';'),
    ';'
  ),

  interface_class_method: $ => seq('pure', 'virtual', $._method_prototype, ';'),

  package_declaration: $ => seq(
    repeat($.attribute_instance),
    'package', optional($.lifetime), $.package_identifier, ';',
    optional($.timeunits_declaration),
    repseq(repeat($.attribute_instance), $._package_item),
    'endpackage', optseq(':', $.package_identifier)
  ),

  timeunits_declaration: $ => choice(
    prec.left(seq('timeunit', $.time_literal, optseq('/', $.time_literal), ';')),
    prec.left(seq('timeprecision', $.time_literal, ';')),
    prec.left(seq('timeunit', $.time_literal, ';', 'timeprecision', $.time_literal, ';')),
    prec.left(seq('timeprecision', $.time_literal, ';', 'timeunit', $.time_literal, ';'))
  ),

  /* A.1.3 Module parameters and ports */

  parameter_port_list: $ => seq(
    '#', '(',
    optional(choice(
      seq($.list_of_param_assignments, repseq(',', $.parameter_port_declaration)),
      sep1(',', $.parameter_port_declaration)
    )),
    ')'
  ),

  parameter_port_declaration: $ => choice(
    $._any_parameter_declaration,
    seq($.data_type, $.list_of_param_assignments),
    seq('type', $.list_of_type_assignments)
  ),

  list_of_ports: $ => seq(
    '(',
    optional(sep1(',', seq(
      optional($.line_compiler_directive),
      $.port,
      optional($.line_compiler_directive)
    ))),
    ')'
  ),

  list_of_port_declarations: $ => seq(
    '(',
    optional(sep1(',', seq(
      repeat($.attribute_instance),
      $.ansi_port_declaration
    ))),
    ')'
  ),

  port_declaration: $ => seq(
    repeat($.attribute_instance),
    choice(
      $.inout_declaration,
      $.input_declaration,
      $.output_declaration,
      $.ref_declaration,
      $.interface_port_declaration
    )
  ),

  port: $ => choice(
    $._port_expression,
    seq('.', $.port_identifier, '(', optional($._port_expression), ')')
  ),

  _port_expression: $ => choice(
    $.port_reference,
    seq('{', sep1(',', $.port_reference), '}')
  ),

  port_reference: $ => seq(
    $.port_identifier,
    optional($.constant_select1)
  ),

  port_direction: $ => choice('input', 'output', 'inout', 'ref'),

  net_port_header1: $ => choice(
    seq(optional($.port_direction), $.net_port_type1),
    $.port_direction
  ),

  variable_port_header: $ => seq(
    optional($.port_direction),
    $._variable_port_type
  ),

  interface_port_header: $ => seq(
    choice(
      $.interface_identifier,
      'interface'
    ),
    optseq('.', $.modport_identifier)
  ),

  ansi_port_declaration: $ => choice(
    seq(
      optional(choice($.net_port_header1, $.interface_port_header)),
      $.port_identifier,
      repeat($.unpacked_dimension),
      optseq('=', $.constant_expression)
    ),
    seq(
      optional($.variable_port_header),
      $.port_identifier,
      repeat($._variable_dimension),
      optseq('=', $.constant_expression)
    ),
    seq(
      optional($.port_direction), '.', $.port_identifier,
      '(', optional($.expression), ')'
    )
  ),

  /* A.1.4 Module items */

  elaboration_system_task: $ => choice(
    seq(
      '$fatal',
      optseq(
        '(', $.finish_number, optseq(',', $.list_of_arguments), ')'
      ),
      ';'
    ),
    seq(
      choice('$error', '$warning', '$info'),
      optional($.list_of_arguments_parent),
      ';'
    )
  ),

  finish_number: $ => choice('0', '1', '2'),

  _module_common_item: $ => choice(
    $._module_or_generate_item_declaration,
    $.interface_instantiation,
    $.program_instantiation,
    $._assertion_item,
    $.bind_directive,
    $.continuous_assign,
    $.net_alias,
    $.initial_construct,
    $.final_construct,
    $.always_construct,
    $.loop_generate_construct,
    $._conditional_generate_construct,
    $.elaboration_system_task
  ),

  _module_item: $ => choice(
    seq($.port_declaration, ';'),
    $._non_port_module_item
  ),

  module_or_generate_item: $ => seq(
    repeat($.attribute_instance),
    choice(
      $.parameter_override,
      $.gate_instantiation,
      $.udp_instantiation,
      $.module_instantiation,
      $._module_common_item
    )
  ),

  _module_or_generate_item_declaration: $ => choice(
    $.package_or_generate_item_declaration,
    $.genvar_declaration,
    $.clocking_declaration,
    seq('default', 'clocking', $.clocking_identifier, ';'),
    seq('default', 'disable', 'iff', $.expression_or_dist, ';')
  ),

  _non_port_module_item: $ => choice(
    $._directives,
    $.generate_region,
    $.module_or_generate_item,
    $.specify_block,
    seq(repeat($.attribute_instance), $.specparam_declaration),
    $.program_declaration,
    $.module_declaration,
    $.interface_declaration,
    $.timeunits_declaration
  ),

  parameter_override: $ => seq(
    'defparam',
    $.list_of_defparam_assignments,
    ';'
  ),

  bind_directive: $ => seq(
    'bind',
    choice(
      seq(
        $.bind_target_scope,
        optseq(':', $.bind_target_instance_list)
      ),
      $.bind_target_instance
    ),
    $._bind_instantiation,
    ';'
  ),

  bind_target_scope: $ => choice(
    $._module_identifier
    // $.interface_identifier
  ),

  bind_target_instance: $ => seq(
    $.hierarchical_identifier,
    optional($.constant_bit_select1)
  ),

  bind_target_instance_list: $ => sep1(',', $.bind_target_instance),

  _bind_instantiation: $ => choice(
    $.program_instantiation,
    $.module_instantiation,
    $.interface_instantiation,
    $.checker_instantiation
  ),

  /* A.1.5 Configuration source text */

  config_declaration: $ => seq(
    'config', $.config_identifier, ';',
    repseq($.local_parameter_declaration, ';'),
    $.design_statement,
    repeat($.config_rule_statement),
    'endconfig', optseq(':', $.config_identifier)
  ),

  design_statement: $ => seq(
    'design',
    repseq(
      optseq($.library_identifier, '.'),
      $.cell_identifier
    ),
    ';'
  ),

  config_rule_statement: $ => choice(
    seq($.default_clause, $.liblist_clause, ';'),
    seq($.inst_clause, $.liblist_clause, ';'),
    seq($.inst_clause, $.use_clause, ';'),
    seq($.cell_clause, $.liblist_clause, ';'),
    seq($.cell_clause, $.use_clause, ';')
  ),

  default_clause: $ => 'default',

  inst_clause: $ => seq('instance', $.inst_name),

  inst_name: $ => seq($.topmodule_identifier, repseq('.', $.instance_identifier)),

  cell_clause: $ => seq('cell', optseq($.library_identifier, '.'), $.cell_identifier),

  liblist_clause: $ => seq('liblist', repeat($.library_identifier)),

  use_clause: $ => seq(
    'use',
    choice(
      sep1(',', $.named_parameter_assignment),
      seq(
        optseq($.library_identifier, '.'),
        $.cell_identifier,
        optional(sep1(',', $.named_parameter_assignment))
      )
    ),
    optseq(':', 'config')
  ),

  /* A.1.6 Interface items */

  interface_or_generate_item: $ => choice(
    seq(repeat($.attribute_instance), $._module_common_item),
    seq(repeat($.attribute_instance), $.extern_tf_declaration)
  ),

  extern_tf_declaration: $ => choice(
    seq('extern', $._method_prototype, ';'),
    seq('extern', 'forkjoin', $.task_prototype, ';')
  ),

  interface_item: $ => choice(
    seq($.port_declaration, ';'),
    $._non_port_interface_item
  ),

  _non_port_interface_item: $ => choice(
    $.generate_region,
    $.interface_or_generate_item,
    $.program_declaration,
    $.modport_declaration,
    $.interface_declaration,
    $.timeunits_declaration
  ),

  /* A.1.7 Program items */

  program_item: $ => choice(
    seq($.port_declaration, ';'),
    $.non_port_program_item
  ),

  non_port_program_item: $ => choice(
    seq(repeat($.attribute_instance), $.continuous_assign),
    seq(repeat($.attribute_instance), $._module_or_generate_item_declaration),
    seq(repeat($.attribute_instance), $.initial_construct),
    seq(repeat($.attribute_instance), $.final_construct),
    seq(repeat($.attribute_instance), $.concurrent_assertion_item),
    $.timeunits_declaration,
    $._program_generate_item
  ),

  _program_generate_item: $ => choice(
    $.loop_generate_construct,
    $._conditional_generate_construct,
    $.generate_region,
    $.elaboration_system_task
  ),

  /* A.1.8 Checker items */

  checker_port_list: $ => sep1(',', $.checker_port_item),

  checker_port_item: $ => seq(
    repeat($.attribute_instance),
    optional($.checker_port_direction),
    optional($.property_formal_type1),
    $.formal_port_identifier,
    repeat($._variable_dimension),
    optseq('=', $._property_actual_arg)
  ),

  checker_port_direction: $ => choice('input', 'output'),

  _checker_or_generate_item: $ => choice(
    $.checker_or_generate_item_declaration,
    $.initial_construct,
    $.always_construct,
    $.final_construct,
    $._assertion_item,
    $.continuous_assign,
    $._checker_generate_item
  ),

  checker_or_generate_item_declaration: $ => choice(
    seq(optional('rand'), $.data_declaration),
    $.function_declaration,
    $.checker_declaration,
    $._assertion_item_declaration,
    $.covergroup_declaration,
    $.genvar_declaration,
    $.clocking_declaration,
    seq('default', 'clocking', $.clocking_identifier, ';'),
    prec.right(PREC.iff, seq('default', 'disable', 'iff', $.expression_or_dist, ';')),
    ';'
  ),

  _checker_generate_item: $ => choice(
    $.loop_generate_construct,
    $._conditional_generate_construct,
    $.generate_region,
    $.elaboration_system_task
  ),

  /* A.1.9 Class items */

  class_item: $ => choice(
    $._directives,
    seq(repeat($.attribute_instance), $.class_property),
    seq(repeat($.attribute_instance), $.class_method),
    seq(repeat($.attribute_instance), $._class_constraint),
    seq(repeat($.attribute_instance), $.class_declaration),
    seq(repeat($.attribute_instance), $.covergroup_declaration),
    seq($._any_parameter_declaration, ';'),
    ';'
  ),

  class_property: $ => choice(
    seq(repeat($._property_qualifier), $.data_declaration),
    seq(
      'const',
      repeat($.class_item_qualifier),
      $.data_type,
      $.const_identifier,
      optseq('=', $.constant_expression),
      ';'
    )
  ),

  class_method: $ => choice(
    seq(repeat($.method_qualifier), $.task_declaration),
    seq(repeat($.method_qualifier), $.function_declaration),
    seq('pure', 'virtual', repeat($.class_item_qualifier), $._method_prototype, ';'),
    seq('extern', repeat($.method_qualifier), $._method_prototype, ';'),
    seq(repeat($.method_qualifier), $.class_constructor_declaration),
    seq('extern', repeat($.method_qualifier), $.class_constructor_prototype)
  ),

  class_constructor_prototype: $ => seq(
    'function', 'new', optseq('(', optional($.tf_port_list), ')'), ';'
  ),

  _class_constraint: $ => choice(
    $.constraint_prototype,
    $.constraint_declaration
  ),

  class_item_qualifier: $ => choice('static', 'protected', 'local'),

  _property_qualifier: $ => choice(
    $.random_qualifier,
    $.class_item_qualifier
  ),

  random_qualifier: $ => choice('rand', 'randc'),

  method_qualifier: $ => choice(
    seq(optional('pure'), 'virtual'),
    $.class_item_qualifier
  ),

  _method_prototype: $ => choice(
    $.task_prototype,
    $.function_prototype
  ),

  class_constructor_declaration: $ => seq(
    'function',
    optional($.class_scope),
    'new',
    optseq('(', optional($.tf_port_list), ')'),
    ';',
    repeat($.block_item_declaration),
    optseq(
      'super', '.', 'new',
      optional($.list_of_arguments_parent),
      ';'
    ),
    repeat($.function_statement_or_null),
    'endfunction', optseq(':', 'new')
  ),

  /* A.1.10 Constraints */

  constraint_declaration: $ => seq(
    optional('static'),
    'constraint',
    $.constraint_identifier,
    $.constraint_block
  ),

  constraint_block: $ => seq('{', repeat($.constraint_block_item), '}'),

  constraint_block_item: $ => choice(
    seq('solve', $.solve_before_list, 'before', $.solve_before_list, ';'),
    $.constraint_expression
  ),

  solve_before_list: $ => sep1(',', $.constraint_primary),

  constraint_primary: $ => seq(
    optional(choice(
      seq($.implicit_class_handle, '.'),
      $.class_scope
    )),
    $.hierarchical_identifier,
    optional($.select1)
  ),

  constraint_expression: $ => choice(
    seq(optional('soft'), $.expression_or_dist, ';'),
    seq($.uniqueness_constraint, ';'),
    prec.right(PREC.IMPLICATION, seq($.expression, '–>', $.constraint_set)),
    prec.left(seq(
      'if', '(', $.expression, ')', $.constraint_set,
      optseq('else', $.constraint_set)
    )),
    seq(
      'foreach', '(',
      $.ps_or_hierarchical_array_identifier,
      '[', optional($.loop_variables1), ']',
      ')',
      $.constraint_set
    ),
    seq('disable', 'soft', $.constraint_primary, ';')
  ),

  uniqueness_constraint: $ => seq(
    'unique', '{', $.open_range_list, '}'
  ),

  constraint_set: $ => choice(
    $.constraint_expression,
    seq('{', repeat($.constraint_expression), '}')
  ),

  dist_list: $ => sep1(',', $.dist_item),

  dist_item: $ => seq($.value_range, optional($.dist_weight)),

  dist_weight: $ => seq(choice(':=', ':/'), $.expression),

  constraint_prototype: $ => seq(
    optional($.constraint_prototype_qualifier),
    optional('static'),
    'constraint',
    $.constraint_identifier,
    ';'
  ),

  constraint_prototype_qualifier: $ => choice('extern', 'pure'),

  extern_constraint_declaration: $ => seq(
    optional('static'),
    'constraint',
    $.class_scope,
    $.constraint_identifier,
    $.constraint_block
  ),

  identifier_list: $ => sep1(',', $._identifier),


  /* A.1.11 Package items */

  _package_item: $ => choice(
    $.package_or_generate_item_declaration,
    $.anonymous_program,
    $.package_export_declaration,
    $.timeunits_declaration
  ),

  package_or_generate_item_declaration: $ => choice(
    $.net_declaration,
    $.data_declaration,
    $.task_declaration,
    $.function_declaration,
    $.checker_declaration,
    $.dpi_import_export,
    $.extern_constraint_declaration,
    $.class_declaration,
    $.interface_class_declaration, // not in spec
    $.class_constructor_declaration,
    seq($._any_parameter_declaration, ';'),
    $.covergroup_declaration,
    $.overload_declaration,
    $._assertion_item_declaration,
    ';'
  ),

  anonymous_program: $ => seq(
    'program', ';', repeat($.anonymous_program_item), 'endprogram'
  ),

  anonymous_program_item: $ => choice(
    $.task_declaration,
    $.function_declaration,
    $.class_declaration,
    $.covergroup_declaration,
    $.class_constructor_declaration,
    ';'
  ),

  /* A.2 Declarations */

  /* A.2.1 Declaration types */

  /* A.2.1.1 Module parameter declarations */

  local_parameter_declaration: $ => seq(
    'localparam',
    choice(
      seq(
        optional($.data_type_or_implicit1),
        $.list_of_param_assignments
      ),
      seq('type', $.list_of_type_assignments)
    )
  ),

  parameter_declaration: $ => seq(
    'parameter',
    choice(
      seq(
        optional($.data_type_or_implicit1),
        $.list_of_param_assignments
      ),
      seq('type', $.list_of_type_assignments)
    )
  ),

  _any_parameter_declaration: $ => choice(
    $.local_parameter_declaration,
    $.parameter_declaration
  ),

  specparam_declaration: $ => seq(
    'specparam',
    optional($.packed_dimension),
    $.list_of_specparam_assignments,
    ';'
  ),

  /* A.2.1.2 Port declarations */

  inout_declaration: $ => seq(
    'inout', optional($.net_port_type1), $.list_of_port_identifiers
  ),

  input_declaration: $ => seq(
    'input',
    choice(
      seq(optional($.net_port_type1), $.list_of_port_identifiers),
      seq(optional($._variable_port_type), $.list_of_variable_identifiers)
    )
  ),

  output_declaration: $ => seq(
    'output',
    choice(
      seq(optional($.net_port_type1), $.list_of_port_identifiers),
      seq(optional($._variable_port_type), $.list_of_variable_port_identifiers)
    )
  ),

  interface_port_declaration: $ => seq(
    $.interface_identifier,
    optseq('.', $.modport_identifier),
    $.list_of_interface_identifiers
  ),

  ref_declaration: $ => seq(
    'ref', $._variable_port_type, $.list_of_variable_identifiers
  ),

  // A.2.1.3 Type declarations

  data_declaration: $ => choice(
    seq(
      optional('const'),
      optional('var'),
      optional($.lifetime),
      optional($.data_type_or_implicit1),
      $.list_of_variable_decl_assignments,
      ';'
    ),
    $.type_declaration,
    $.package_import_declaration,
    $.net_type_declaration
  ),

  package_import_declaration: $ => seq(
    'import', sep1(',', $.package_import_item), ';'
  ),

  package_import_item: $ => seq(
    $.package_identifier, '::', choice($._identifier, '*')
  ),

  package_export_declaration: $ => seq(
    'export', choice('*::*', sep1(',', $.package_import_item)), ';'
  ),

  genvar_declaration: $ => seq(
    'genvar', $.list_of_genvar_identifiers, ';'
  ),

  net_declaration: $ => choice(
    seq(
      $.net_type,
      optional(choice($.drive_strength, $.charge_strength)),
      optional(choice('vectored', 'scalared')),
      optional($.data_type_or_implicit1),
      optional($.delay3),
      $.list_of_net_decl_assignments,
      ';'
    ),
    seq(
      $._net_type_identifier,
      optional($.delay_control),
      $.list_of_net_decl_assignments,
      ';'
    ),
    seq(
      'interconnect',
      optional($.implicit_data_type1),
      optseq('#', $.delay_value),
      sep1(',', seq($._net_identifier, repeat($.unpacked_dimension))),
      ';'
    )
  ),

  type_declaration: $ => seq(
    'typedef',
    choice(
      seq($.data_type, $._type_identifier, repeat($._variable_dimension)),
      seq(
        $.interface_instance_identifier, optional($.constant_bit_select1),
        '.', $._type_identifier, $._type_identifier
      ),
      seq(
        optional(choice(
          'enum', 'struct', 'union', 'class', seq('interface', 'class')
        )),
        $._type_identifier
      )
    ),
    ';'
  ),

  net_type_declaration: $ => seq(
    'nettype',
    choice(
      seq(
        $.data_type,
        $._net_type_identifier,
        optseq(
          'with',
          optional(choice($.package_scope, $.class_scope)),
          $.tf_identifier
        )
      ),
      seq(
        optional(choice($.package_scope, $.class_scope)),
        $._net_type_identifier,
        $._net_type_identifier
      )
    ),
    ';'
  ),

  lifetime: $ => choice('static', 'automatic'),


  /* A.2.2 Declaration data types */

  /* A.2.2.1 Net and variable types */

  casting_type: $ => choice(
    $._simple_type,
    $.constant_primary,
    $._signing,
    'string',
    'const'
  ),

  data_type: $ => choice(
    seq($.integer_vector_type, optional($._signing), repeat($.packed_dimension)),
    seq($.integer_atom_type, optional($._signing)),
    $.non_integer_type,
    seq(
      $.struct_union,
      optseq('packed', optional($._signing)),
      '{', repeat1($.struct_union_member), '}',
      repeat($.packed_dimension)
    ),
    seq(
      'enum', optional($.enum_base_type),
      '{', sep1(',', $.enum_name_declaration), '}',
      repeat($.packed_dimension)
    ),
    'string',
    'chandle',
    prec.left(seq(
      'virtual', optional('interface'),
      $.interface_identifier,
      optional($.parameter_value_assignment),
      optseq('.', $.modport_identifier)
    )),
    seq(
      optional(choice($.class_scope, $.package_scope)),
      $._type_identifier,
      repeat($.packed_dimension)
    ),
    $.class_type,
    'event',
    $.ps_covergroup_identifier,
    $.type_reference
  ),

  data_type_or_implicit1: $ => choice(
    $.data_type,
    $.implicit_data_type1
  ),

  implicit_data_type1: $ => choice( // reordered : repeat -> repeat1
    seq($._signing, repeat($.packed_dimension)),
    repeat1($.packed_dimension)
  ),

  enum_base_type: $ => choice(
    seq(
      $.integer_atom_type, optional($._signing)
    ),
    seq(
      $.integer_vector_type, optional($._signing), optional($.packed_dimension)
    ),
    seq(
      $._type_identifier, optional($.packed_dimension)
    )
  ),

  enum_name_declaration: $ => seq(
    $.enum_identifier,
    optseq(
      '[', $.integral_number, optseq(':', $.integral_number), ']'
    ),
    optseq('=', $.constant_expression)
  ),

  class_scope: $ => seq($.class_type, '::'),

  // class_type: $ => prec.left(PREC.PARENT, seq(
  class_type: $ => prec.right(seq(
    $.ps_class_identifier,
    optional($.parameter_value_assignment),
    repseq(
      '::',
      $.class_identifier,
      optional($.parameter_value_assignment)
    )
  )),

  _integer_type: $ => choice(
    $.integer_vector_type,
    $.integer_atom_type
  ),

  integer_atom_type: $ => choice('byte', 'shortint', 'int', 'longint', 'integer', 'time'),

  integer_vector_type: $ => choice('bit', 'logic', 'reg'),

  non_integer_type: $ => choice('shortreal', 'real', 'realtime'),

  net_type: $ => choice('supply0', 'supply1', 'tri', 'triand', 'trior', 'trireg', 'tri0', 'tri1', 'uwire', 'wire', 'wand', 'wor'),

  net_port_type1: $ => choice(
    prec.left(-1, seq($.net_type, $.data_type_or_implicit1)),
    $.net_type,
    $.data_type_or_implicit1,

    $._net_type_identifier,
    seq('interconnect', optional($.implicit_data_type1))
  ),

  _variable_port_type: $ => $._var_data_type,

  _var_data_type: $ => prec.left(choice(
    $.data_type,
    seq('var', optional($.data_type_or_implicit1))
  )),

  _signing: $ => choice('signed', 'unsigned'),

  _simple_type: $ => choice(
    $._integer_type,
    $.non_integer_type,
    $.ps_type_identifier,
    $.ps_parameter_identifier
  ),

  struct_union_member: $ => seq(
    repeat($.attribute_instance),
    optional($.random_qualifier),
    $.data_type_or_void,
    $.list_of_variable_decl_assignments,
    ';'
  ),

  data_type_or_void: $ => choice(
    $.data_type,
    'void'
  ),

  struct_union: $ => choice(
    'struct',
    seq('union', optional('tagged'))
  ),

  type_reference: $ => seq(
    'type', '(',
    choice(
      $.expression,
      $.data_type
    ),
    ')'
  ),

  // A.2.2.2 Strengths

  drive_strength: $ => seq(
    '(',
    choice(
      seq($.strength0, ',', $.strength1),
      seq($.strength1, ',', $.strength0),
      seq($.strength0, ',', 'highz1'),
      seq($.strength1, ',', 'highz0'),
      seq('highz0', ',', $.strength1),
      seq('highz1', ',', $.strength0)
    ),
    ')'
  ),

  strength0: $ => choice('supply0', 'strong0', 'pull0', 'weak0'),

  strength1: $ => choice('supply1', 'strong1', 'pull1', 'weak1'),

  charge_strength: $ => seq('(', choice('small', 'medium', 'large'), ')'),

  // A.2.2.3 Delays

  delay3: $ => seq('#', choice(
    $.delay_value,
    seq(
      '(', $.mintypmax_expression,
      optseq($.mintypmax_expression,
        optional($.mintypmax_expression)
      ),
      ')'
    )
  )),

  delay2: $ => seq('#', choice(
    $.delay_value,
    seq('(', $.mintypmax_expression, optional($.mintypmax_expression), ')')
  )),

  delay_value: $ => choice(
    $.unsigned_number,
    $.real_number,
    $.ps_identifier,
    $.time_literal,
    '1step'
  ),

  /* A.2.3 Declaration lists */

  list_of_defparam_assignments: $ => sep1(',', $.defparam_assignment),

  list_of_genvar_identifiers: $ => sep1(',', $.genvar_identifier),

  list_of_interface_identifiers: $ => sep1(',', seq(
    $.interface_identifier,
    repeat($.unpacked_dimension)
  )),

  list_of_net_decl_assignments: $ => sep1(',', $.net_decl_assignment),

  list_of_param_assignments: $ => sep1(',', $.param_assignment),

  list_of_port_identifiers: $ => sep1(',', seq(
    $.port_identifier,
    repeat($.unpacked_dimension)
  )),

  list_of_udp_port_identifiers: $ => sep1(',', $.port_identifier),

  list_of_specparam_assignments: $ => sep1(',', $.specparam_assignment),

  list_of_tf_variable_identifiers: $ => sep1(',', seq(
    $.port_identifier,
    repeat($._variable_dimension),
    optseq('=', $.expression)
  )),

  list_of_type_assignments: $ => sep1(',', $.type_assignment),

  list_of_variable_decl_assignments: $ => sep1(',', $.variable_decl_assignment),

  list_of_variable_identifiers: $ => sep1(',', seq(
    $._variable_identifier,
    repeat($._variable_dimension)
  )),

  list_of_variable_port_identifiers: $ => sep1(',', seq(
    $.port_identifier,
    repeat($._variable_dimension),
    optseq('=', $.constant_expression)
  )),

  /* A.2.4 Declaration assignments */

  defparam_assignment: $ => seq(
    $._hierarchical_parameter_identifier,
    '=',
    $.constant_mintypmax_expression
  ),

  net_decl_assignment: $ => prec.left(PREC.ASSIGN, seq(
    $._net_identifier,
    repeat($.unpacked_dimension),
    optseq('=', $.expression)
  )),

  param_assignment: $ => seq(
    $.parameter_identifier,
    repeat($.unpacked_dimension),
    optseq('=', $.constant_param_expression)
  ),

  specparam_assignment: $ => choice(
    seq($.specparam_identifier, '=', $.constant_mintypmax_expression),
    $.pulse_control_specparam
  ),

  type_assignment: $ => seq(
    $._type_identifier,
    optseq('=', $.data_type)
  ),

  pulse_control_specparam: $ => choice(
    seq(
      'PATHPULSE$=',
      '(',
      $.reject_limit_value,
      optseq(',', $.error_limit_value),
      ')'
    )
    // seq(
    //   'PATHPULSE$',
    //   $.specify_input_terminal_descriptor,
    //   '$',
    //   $.specify_output_terminal_descriptor,
    //   '=', '(', $.reject_limit_value, optseq(',', $.error_limit_value), ')'
    // )
  ),

  error_limit_value: $ => $.limit_value,

  reject_limit_value: $ => $.limit_value,

  limit_value: $ => $.constant_mintypmax_expression,

  variable_decl_assignment: $ => choice(
    seq(
      $._variable_identifier,
      repeat($._variable_dimension),
      optseq('=', $.expression)
    ),
    seq(
      $.dynamic_array_variable_identifier,
      $.unsized_dimension,
      repeat($._variable_dimension),
      optseq('=', $.dynamic_array_new)
    ),
    seq(
      $.class_variable_identifier,
      optseq('=', $.class_new)
    )
  ),

  class_new: $ => choice(
    seq(
      optional($.class_scope), 'new', optional($.list_of_arguments_parent)
    ),
    seq('new', $.expression)
  ),

  dynamic_array_new: $ => seq(
    'new', '[', $.expression, ']', optseq('(', $.expression, ')')
  ),

  // A.2.5 Declaration ranges

  unpacked_dimension: $ => seq(
    '[', choice(
      $.constant_range,
      $.constant_expression
    ), ']'
  ),

  packed_dimension: $ => choice(
    seq('[', $.constant_range, ']'),
    $.unsized_dimension
  ),

  associative_dimension: $ => seq(
    '[', choice($.data_type, '*'), ']'
  ),

  _variable_dimension: $ => choice(
    $.unsized_dimension,
    $.unpacked_dimension,
    $.associative_dimension,
    $.queue_dimension
  ),

  queue_dimension: $ => seq(
    '[', '$', optseq(':', $.constant_expression), ']'
  ),

  unsized_dimension: $ => seq('[', ']'),

  // A.2.6 Function declarations

  function_data_type_or_implicit1: $ => choice(
    $.data_type_or_void,
    $.implicit_data_type1
  ),

  function_declaration: $ => seq(
    'function',
    optional($.lifetime),
    $.function_body_declaration
  ),

  function_body_declaration: $ => seq(
    optional($.function_data_type_or_implicit1),
    optional(choice(
      seq($.interface_identifier, '.'),
      $.class_scope
    )),
    $.function_identifier,
    choice(
      seq(
        ';',
        repeat($.tf_item_declaration)
      ),
      seq(
        '(', optional($.tf_port_list), ')', ';',
        repeat($.block_item_declaration)
      )
    ),
    repeat($.function_statement_or_null),
    'endfunction',
    optseq(':', $.function_identifier)
  ),

  function_prototype: $ => seq(
    'function',
    $.data_type_or_void,
    $.function_identifier,
    optseq(
      '(', optional($.tf_port_list), ')'
    )
  ),

  dpi_import_export: $ => choice(
    seq(
      'import',
      $.dpi_spec_string,
      optional($.dpi_function_import_property),
      optseq($.c_identifier, '='),
      $.dpi_function_proto,
      ';'
    ),
    seq(
      'import',
      $.dpi_spec_string,
      optional($.dpi_task_import_property),
      optseq($.c_identifier, '='),
      $.dpi_task_proto,
      ';'
    ),
    seq(
      'export',
      $.dpi_spec_string,
      optseq($.c_identifier, '='),
      'function',
      $.function_identifier,
      ';'
    ),
    seq(
      'export',
      $.dpi_spec_string,
      optseq($.c_identifier, '='),
      'task',
      $.task_identifier,
      ';'
    )
  ),

  dpi_spec_string: $ => choice('"DPI-C"', '"DPI"'),

  dpi_function_import_property: $ => choice('context', 'pure'),

  dpi_task_import_property: $ => 'context',

  dpi_function_proto: $ => $.function_prototype,

  dpi_task_proto: $ => $.task_prototype,


  // A.2.7 Task declarations

  task_declaration: $ => seq(
    'task',
    optional($.lifetime),
    $.task_body_declaration
  ),

  task_body_declaration: $ => seq(
    optional(choice(
      seq($.interface_identifier, '.'),
      $.class_scope
    )),
    $.task_identifier,
    choice(
      seq(
        ';',
        repeat($.tf_item_declaration)
      ),
      seq(
        '(', optional($.tf_port_list), ')', ';',
        repeat($.block_item_declaration)
      )
    ),
    repeat($.statement_or_null),
    'endtask',
    optseq(':', $.task_identifier)
  ),

  tf_item_declaration: $ => choice(
    $.block_item_declaration,
    $.tf_port_declaration
  ),

  tf_port_list: $ => sep1(',', $.tf_port_item1),

  tf_port_item1: $ => seq(
    repeat($.attribute_instance),
    optional($.tf_port_direction),
    optional('var'),
    choice(
      seq(
        $.data_type_or_implicit1,
        optseq(
          $.port_identifier,
          repeat($._variable_dimension),
          optseq('=', $.expression)
        )
      ),
      seq(
        $.port_identifier,
        repeat($._variable_dimension),
        optseq('=', $.expression)
      )
    )
  ),

  tf_port_direction: $ => choice(
    $.port_direction,
    seq('const', 'ref')
  ),

  tf_port_declaration: $ => seq(
    repeat($.attribute_instance),
    $.tf_port_direction,
    optional('var'),
    optional($.data_type_or_implicit1),
    $.list_of_tf_variable_identifiers,
    ';'
  ),

  task_prototype: $ => seq(
    'task',
    $.task_identifier,
    optseq('(', optional($.tf_port_list), ')')
  ),


  // A.2.8 Block item declarations

  block_item_declaration: $ => seq(
    repeat($.attribute_instance),
    choice(
      $.data_declaration,
      seq($._any_parameter_declaration, ';'),
      $.overload_declaration,
      $.let_declaration
    )
  ),

  overload_declaration: $ => seq(
    'bind',
    $.overload_operator,
    'function',
    $.data_type,
    $.function_identifier,
    '(',
    $.overload_proto_formals,
    ')',
    ';'
  ),

  overload_operator: $ => choice('+', '++', '–', '––', '*', '**', '/', '%', '==', '!=', '<', '<=', '>', '>=', '='),

  overload_proto_formals: $ => sep1(',', $.data_type),

  /* A.2.9 Interface declarations */

  modport_declaration: $ => seq('modport', sep1(',', $.modport_item), ';'),

  modport_item: $ => seq(
    $.modport_identifier,
    '(', sep1(',', $.modport_ports_declaration), ')'
  ),

  modport_ports_declaration: $ => seq(
    repeat($.attribute_instance),
    choice(
      $.modport_simple_ports_declaration,
      $.modport_tf_ports_declaration,
      $.modport_clocking_declaration
    )
  ),

  modport_clocking_declaration: $ => seq('clocking', $.clocking_identifier),

  modport_simple_ports_declaration: $ => seq(
    $.port_direction,
    sep1(',', $.modport_simple_port)
  ),

  modport_simple_port: $ => choice(
    $.port_identifier,
    seq('.', $.port_identifier, '(', optional($.expression), ')')
  ),

  modport_tf_ports_declaration: $ => seq(
    $.import_export, sep1(',', $._modport_tf_port)
  ),

  _modport_tf_port: $ => choice(
    $._method_prototype,
    $.tf_identifier
  ),

  import_export: $ => choice('import', 'export'),

  // A.2.10 Assertion declarations

  concurrent_assertion_item: $ => choice(
    seq(
      optseq($._block_identifier, ':'),
      $._concurrent_assertion_statement
    ),
    $.checker_instantiation
  ),

  _concurrent_assertion_statement: $ => choice(
    $.assert_property_statement,
    $.assume_property_statement,
    $.cover_property_statement,
    $.cover_sequence_statement,
    $.restrict_property_statement
  ),

  assert_property_statement: $ => seq(
    'assert', 'property', '(', $.property_spec, ')', $.action_block
  ),

  assume_property_statement: $ => seq(
    'assume', 'property', '(', $.property_spec, ')', $.action_block
  ),

  cover_property_statement: $ => seq(
    'cover', 'property', '(', $.property_spec, ')', $.statement_or_null
  ),

  expect_property_statement: $ => seq(
    'expect', '(', $.property_spec, ')', $.action_block
  ),

  cover_sequence_statement: $ => seq(
    'cover', 'sequence', '(',
    optional($.clocking_event),
    optional(prec.right(PREC.iff, seq(
      'disable', 'iff', '(', $.expression_or_dist, ')'
    ))),
    $.sequence_expr,
    ')',
    $.statement_or_null
  ),

  restrict_property_statement: $ => seq(
    'restrict', 'property', '(', $.property_spec, ')', ';'
  ),

  property_instance: $ => seq(
    $.ps_or_hierarchical_property_identifier,
    optseq('(', optional($.property_list_of_arguments), ')')
  ),

  property_list_of_arguments: $ => choice(
    seq(
      sep1(',', optional($._property_actual_arg)),
      repeat1(seq( // TODO remove 1
        ',', '.', $._identifier, '(', optional($._property_actual_arg), ')'
      ))
    ),
    sep1(',', seq(
      '.', $._identifier, '(', optional($._property_actual_arg), ')'
    ))
  ),

  _property_actual_arg: $ => choice(
    $.property_expr,
    $._sequence_actual_arg
  ),

  _assertion_item_declaration: $ => choice(
    $.property_declaration,
    $.sequence_declaration,
    $.let_declaration
  ),

  property_declaration: $ => seq(
    'property',
    $.property_identifier,
    optseq('(', optional($.property_port_list), ')'),
    ';',
    repeat($.assertion_variable_declaration),
    $.property_spec,
    optional(';'),
    'endproperty', optseq(':', $.property_identifier)
  ),

  property_port_list: $ => sep1(',', $.property_port_item),

  property_port_item: $ => seq(
    repeat($.attribute_instance),
    optseq(
      'local',
      optional($.property_lvar_port_direction)
    ),
    optional($.property_formal_type1),
    $.formal_port_identifier,
    repeat($._variable_dimension),
    optseq('=', $._property_actual_arg)
  ),

  property_lvar_port_direction: $ => 'input',

  property_formal_type1: $ => choice(
    $.sequence_formal_type1,
    'property'
  ),

  property_spec: $ => seq(
    optional($.clocking_event),
    optional(prec.right(PREC.iff, seq(
      'disable', 'iff', '(', $.expression_or_dist, ')'
    ))),
    $.property_expr
  ),

  property_expr: $ => choice(
    $.sequence_expr,
    seq('strong', '(', $.sequence_expr, ')'),
    seq('weak', '(', $.sequence_expr, ')'),
    prec.left(PREC.PARENT, seq('(', $.property_expr, ')')),

    // FIXME no assosiativity rules per spec
    prec.left(PREC.nexttime, seq('not', $.property_expr)),
    prec.left(PREC.or, seq($.property_expr, 'or', $.property_expr)),
    prec.left(PREC.and, seq($.property_expr, 'and', $.property_expr)),

    prec.right(PREC.INCIDENCE, seq($.sequence_expr, '|->', $.property_expr)),
    prec.right(PREC.INCIDENCE, seq($.sequence_expr, '|=>', $.property_expr)),

    // FIXME no assosiativity rules per spec
    prec.left(seq('if', '(', $.expression_or_dist, ')', $.property_expr, optseq('else', $.property_expr))), // FIXME spec bug ( ) are not red

    seq('case', '(', $.expression_or_dist, ')', repeat1($.property_case_item), 'endcase'),  // FIXME spec bug ( ) are not red
    prec.right(PREC.INCIDENCE, seq($.sequence_expr, '#-#', $.property_expr)),
    prec.right(PREC.INCIDENCE, seq($.sequence_expr, '#=#', $.property_expr)),

    // FIXME no assosiativity rules per spec
    prec.left(PREC.nexttime, seq('nexttime', $.property_expr)),
    prec.left(PREC.nexttime, seq('nexttime', '[', $.constant_expression, ']', $.property_expr)), // FIXME spec bug constant _expression with the space
    prec.left(PREC.nexttime, seq('s_nexttime', $.property_expr)),
    prec.left(PREC.nexttime, seq('s_nexttime', '[', $.constant_expression, ']', $.property_expr)),

    prec.left(PREC.always, seq('always', $.property_expr)),
    prec.left(PREC.always, seq('always', '[', $.cycle_delay_const_range_expression, ']', $.property_expr)),
    prec.left(PREC.always, seq('s_always', '[', $.constant_range, ']', $.property_expr)),
    prec.left(PREC.always, seq('s_eventually', $.property_expr)),
    prec.left(PREC.always, seq('eventually', '[', $.constant_range, ']', $.property_expr)),
    prec.left(PREC.always, seq('s_eventually', '[', $.cycle_delay_const_range_expression, ']', $.property_expr)),

    prec.right(PREC.until, seq($.property_expr,
      choice('until', 's_until', 'until_with', 's_until_with', 'implies'),
      $.property_expr
    )),

    prec.right(PREC.iff,   seq($.property_expr, 'iff', $.property_expr)),

    // FIXME no assosiativity rules per spec
    prec.left(PREC.always, seq(
      choice('accept_on', 'reject_on', 'sync_accept_on', 'sync_reject_on'),
      '(', $.expression_or_dist, ')', $.property_expr
    )),
    // $.property_instance,
    prec.left(seq($.clocking_event, $.property_expr)) // FIXME no assosiativity rules per spec
  ),

  property_case_item: $ => choice(
    seq(
      sep1(',', $.expression_or_dist), ':', $.property_expr, ';'
    ),
    seq(
      'default', optional(':'), $.property_expr, ';'
    )
  ),

  sequence_declaration: $ => seq(
    'sequence',
    $._sequence_identifier,
    optseq(
      '(', optional($.sequence_port_list), ')'
    ),
    ';',
    repeat($.assertion_variable_declaration),
    $.sequence_expr,
    optional(';'),
    'endsequence', optseq(':', $._sequence_identifier)
  ),

  sequence_port_list: $ => sep1(',', $.sequence_port_item),

  sequence_port_item: $ => seq(
    repeat($.attribute_instance),
    optseq(
      'local',
      optional($.sequence_lvar_port_direction)
    ),
    optional($.sequence_formal_type1),
    $.formal_port_identifier,
    repeat($._variable_dimension),
    optseq(
      '=', $._sequence_actual_arg
    )
  ),

  sequence_lvar_port_direction: $ => choice('input', 'inout', 'output'),

  sequence_formal_type1: $ => choice(
    $.data_type_or_implicit1,
    'sequence',
    'untyped'
  ),

  sequence_expr: $ => choice(
    prec.left(sep1(',', $.cycle_delay_range)), // FIXME precedence?
    prec.left(PREC.SHARP2, seq($.sequence_expr, repeat1(seq($.cycle_delay_range, $.sequence_expr)))),
    seq($.expression_or_dist, optional($._boolean_abbrev)),
    seq($.sequence_instance, optional($.sequence_abbrev)),
    prec.left(seq('(', $.sequence_expr, repseq(',', $._sequence_match_item), ')', optional($.sequence_abbrev))),
    prec.left(PREC.and, seq($.sequence_expr, 'and', $.sequence_expr)),
    prec.left(PREC.intersect, seq($.sequence_expr, 'intersect', $.sequence_expr)),
    prec.left(PREC.or, seq($.sequence_expr, 'or', $.sequence_expr)),
    seq('first_match', '(', $.sequence_expr, repseq(',', $._sequence_match_item), ')'),
    prec.right(PREC.throughout, seq($.expression_or_dist, 'throughout', $.sequence_expr)),
    prec.left(PREC.within, seq($.sequence_expr, 'within', $.sequence_expr)),
    prec.left(seq($.clocking_event, $.sequence_expr)) // FIXME precedence?
  ),

  cycle_delay_range: $ => choice(
    prec.left(seq('##', $.constant_primary)),
    prec.left(seq('##', '[', $.cycle_delay_const_range_expression, ']')),
    '##[*]',
    '##[+]'
  ),

  sequence_method_call: $ => seq($.sequence_instance, '.', $.method_identifier),

  _sequence_match_item: $ => choice(
    $.operator_assignment,
    $.inc_or_dec_expression,
    $.subroutine_call
  ),

  sequence_instance: $ => seq(
    $.ps_or_hierarchical_sequence_identifier,
    optseq('(', optional($.sequence_list_of_arguments), ')')
  ),

  sequence_list_of_arguments: $ => choice(
    // seq(
    //   sep1(',', optional($._sequence_actual_arg)),
    //   repseq(',', '.', $._identifier, '(', optional($._sequence_actual_arg), ')')
    // ),
    sep1(',', seq('.', $._identifier, '(', optional($._sequence_actual_arg), ')'))
  ),

  _sequence_actual_arg: $ => choice(
    $.event_expression,
    $.sequence_expr
  ),

  _boolean_abbrev: $ => choice(
    $.consecutive_repetition,
    $.non_consecutive_repetition,
    $.goto_repetition
  ),

  sequence_abbrev: $ => $.consecutive_repetition,

  consecutive_repetition: $ => choice(
    seq('[*', $._const_or_range_expression, ']'),
    '[*]',
    '[+]'
  ),

  non_consecutive_repetition: $ => seq('[=', $._const_or_range_expression, ']'),

  goto_repetition: $ => seq('[->', $._const_or_range_expression, ']'),

  _const_or_range_expression: $ => choice(
    $.constant_expression,
    $.cycle_delay_const_range_expression
  ),

  cycle_delay_const_range_expression: $ => choice(
    seq($.constant_expression, ':', $.constant_expression),
    seq($.constant_expression, ':', '$')
  ),

  expression_or_dist: $ => seq(
    $.expression,
    optional(prec.left(PREC.RELATIONAL, seq('dist', '{', $.dist_list, '}')))
  ),

  assertion_variable_declaration: $ => seq(
    $._var_data_type,
    $.list_of_variable_decl_assignments,
    ';'
  ),

  // A.2.11 Covergroup declarations

  covergroup_declaration: $ => seq(
    'covergroup', $.covergroup_identifier,
    optseq('(', optional($.tf_port_list), ')'),
    optional($.coverage_event),
    ';',
    repeat($.coverage_spec_or_option),
    'endgroup', optseq(':', $.covergroup_identifier)
  ),

  coverage_spec_or_option: $ => choice(
    seq(repeat($.attribute_instance), $._coverage_spec),
    seq(repeat($.attribute_instance), $.coverage_option, ';')
  ),

  coverage_option: $ => choice(
    seq('option', '.', $.member_identifier, '=', $.expression),
    seq('type_option', '.', $.member_identifier, '=', $.constant_expression)
  ),

  _coverage_spec: $ => choice($.cover_point, $.cover_cross),

  coverage_event: $ => choice(
    $.clocking_event,
    seq('with', 'function', 'sample', '(', optional($.tf_port_list), ')'),
    seq('@@', '(', $.block_event_expression, ')')
  ),

  block_event_expression: $ => choice(
    prec.left(PREC.or, seq($.block_event_expression, 'or', $.block_event_expression)),
    seq('begin', $.hierarchical_btf_identifier),
    seq('end', $.hierarchical_btf_identifier)
  ),

  hierarchical_btf_identifier: $ => choice(
    $._hierarchical_tf_identifier,
    $._hierarchical_block_identifier,
    prec.left(PREC.PARENT, seq(
      choice(seq($.hierarchical_identifier, '.'), $.class_scope),
      $.method_identifier
    ))
  ),

  cover_point: $ => seq(
    optseq(optional($.data_type_or_implicit1), $.cover_point_identifier, ':'),
    'coverpoint', $.expression,
    optional(prec.right(PREC.iff, seq('iff', '(', $.expression, ')'))),
    $.bins_or_empty
  ),

  bins_or_empty: $ => choice(
    seq('{', repeat($.attribute_instance), repseq($.bins_or_options, ';'), '}'),
    ';'
  ),

  bins_or_options: $ => choice(
    $.coverage_option,
    seq(
      'wildcard',
      $.bins_keyword,
      $._bin_identifier,
      optseq('[', optional($._covergroup_expression), ']'),
      '=',
      '{', $.covergroup_range_list, '}',
      optseq('with', '(', $._with_covergroup_expression, ')'),
      optional(prec.right(PREC.iff, seq('iff', '(', $.expression, ')')))
    ),
    seq(
      'wildcard',
      $.bins_keyword,
      $._bin_identifier,
      optseq('[', optional($._covergroup_expression), ']'),
      '=',
      $.cover_point_identifier,
      'with', '(', $._with_covergroup_expression, ')',
      optional(prec.right(PREC.iff, seq('iff', '(', $.expression, ')')))
    ),
    seq(
      'wildcard',
      $.bins_keyword,
      $._bin_identifier,
      optseq('[', optional($._covergroup_expression), ']'),
      '=',
      $._set_covergroup_expression,
      optional(prec.right(PREC.iff, seq('iff', '(', $.expression, ')')))
    ),
    seq(
      'wildcard',
      $.bins_keyword,
      $._bin_identifier,
      optseq('[', ']'),
      '=',
      $.trans_list,
      optional(prec.right(PREC.iff, seq('iff', '(', $.expression, ')')))
    ),
    seq(
      $.bins_keyword,
      $._bin_identifier,
      optseq('[', optional($._covergroup_expression), ']'),
      '=',
      'default',
      optional(prec.right(PREC.iff, seq('iff', '(', $.expression, ')')))
    ),
    seq(
      $.bins_keyword,
      $._bin_identifier,
      '=',
      'default',
      'sequence',
      optional(prec.right(PREC.iff, seq('iff', '(', $.expression, ')')))
    )
  ),

  bins_keyword: $ => choice('bins', 'illegal_bins', 'ignore_bins'),

  trans_list: $ => sep1(',', seq('(', $.trans_set, ')')),

  trans_set: $ => sep1('=>', $.trans_range_list),

  trans_range_list: $ => choice(
    $.trans_item,
    seq($.trans_item, '[*', $.repeat_range, ']'),
    seq($.trans_item, '[–>', $.repeat_range, ']'),
    seq($.trans_item, '[=', $.repeat_range, ']')
  ),

  trans_item: $ => $.covergroup_range_list,

  repeat_range: $ => seq(
    $._covergroup_expression, optseq(':', $._covergroup_expression)
  ),

  cover_cross: $ => seq(
    optseq($.cross_identifier, ':'),
    'cross',
    $.list_of_cross_items,
    optional(prec.right(PREC.iff, seq('iff', '(', $.expression, ')'))),
    $.cross_body
  ),

  list_of_cross_items: $ => seq($._cross_item, ',', sep1(',', $._cross_item)),

  _cross_item: $ => choice(
    $.cover_point_identifier
    // $._variable_identifier
  ),

  cross_body: $ => choice(
    seq('{', repseq($.cross_body_item, ';'), '}'),
    ';'
  ),

  cross_body_item: $ => choice(
    $.function_declaration, // FIXME standard function_declaraton => function_declaration
    seq($.bins_selection_or_option, ';')
  ),

  bins_selection_or_option: $ => choice(
    seq(repeat($.attribute_instance), $.coverage_option),
    seq(repeat($.attribute_instance), $.bins_selection)
  ),

  bins_selection: $ => seq(
    $.bins_keyword, $._bin_identifier, '=', $.select_expression,
    optional(prec.right(PREC.iff, seq('iff', '(', $.expression, ')')))
  ),

  select_expression: $ => choice(
    $.select_condition,
    prec.left(PREC.UNARY, seq('!', $.select_condition)),
    prec.left(PREC.LOGICAL_AND, seq($.select_expression, '&&', $.select_expression)),
    prec.left(PREC.LOGICAL_OR, seq($.select_expression, '||', $.select_expression)),
    prec.left(PREC.PARENT, seq('(', $.select_expression, ')')),
    seq(
      $.select_expression, 'with', '(', $._with_covergroup_expression, ')',
      optseq('matches', $._integer_covergroup_expression)
    ),
    $.cross_identifier,
    seq(
      $._cross_set_expression,
      optseq('matches', $._integer_covergroup_expression)
    )
  ),

  select_condition: $ => seq(
    'binsof', '(', $.bins_expression, ')',
    optseq('intersect', '{', $.covergroup_range_list, '}')
  ),

  bins_expression: $ => choice(
    $._variable_identifier,
    prec.left(PREC.PARENT, seq($.cover_point_identifier, optseq('.', $._bin_identifier)))
  ),

  covergroup_range_list: $ => sep1(',', $.covergroup_value_range),

  covergroup_value_range: $ => choice(
    $._covergroup_expression,
    seq('[', $._covergroup_expression, ':', $._covergroup_expression, ']')
  ),

  _with_covergroup_expression: $ => $._covergroup_expression,

  _set_covergroup_expression: $ => $._covergroup_expression,

  _integer_covergroup_expression: $ => $._covergroup_expression,

  _cross_set_expression: $ => $._covergroup_expression,

  _covergroup_expression: $ => $.expression,

  /* A.2.12 Let declarations */

  let_declaration: $ => seq(
    'let', $.let_identifier,
    optseq('(', optional($.let_port_list), ')'),
    '=', $.expression, ';'
  ),

  let_identifier: $ => $._identifier,

  let_port_list: $ => sep1(',', $.let_port_item),

  let_port_item: $ => seq(
    repeat($.attribute_instance),
    optional($.let_formal_type1),
    $.formal_port_identifier,
    repeat($._variable_dimension),
    optseq('=', $.expression)
  ),

  let_formal_type1: $ => choice(
    $.data_type_or_implicit1,
    'untyped'
  ),

  let_expression: $ => prec.left(seq(
    optional($.package_scope),
    $.let_identifier,
    optseq('(', optional($.let_list_of_arguments), ')')
  )),

  let_list_of_arguments: $ => choice(
    // FIXME empty string
    // seq(
    //   sep1(',', optional($.let_actual_arg)),
    //   repseq(',', '.', $._identifier, '(', optional($.let_actual_arg), ')')
    // ),
    sep1(',', seq('.', $._identifier, '(', optional($.let_actual_arg), ')'))
  ),

  let_actual_arg: $ => $.expression,

  // A.3 Primitive instances

  // A.3.1 Primitive instantiation and instances

  gate_instantiation: $ => seq(
    choice(
      seq(
        $.cmos_switchtype,
        optional($.delay3),
        sep1(',', $.cmos_switch_instance)
      ),
      seq(
        $.enable_gatetype,
        optional($.drive_strength), optional($.delay3),
        sep1(',', $.enable_gate_instance)
      ),
      seq(
        $.mos_switchtype,
        optional($.delay3),
        sep1(',', $.mos_switch_instance)
      ),
      seq(
        $.n_input_gatetype,
        optional($.drive_strength), optional($.delay2),
        sep1(',', $.n_input_gate_instance)
      ),
      seq(
        $.n_output_gatetype,
        optional($.drive_strength), optional($.delay2),
        sep1(',', $.n_output_gate_instance)
      ),
      seq(
        $.pass_en_switchtype,
        optional($.delay2),
        sep1(',', $.pass_enable_switch_instance)
      ),
      seq(
        $.pass_switchtype,
        sep1(',', $.pass_switch_instance)
      ),
      seq(
        'pulldown',
        optional($.pulldown_strength),
        sep1(',', $.pull_gate_instance)
      ),
      seq(
        'pullup',
        optional($.pullup_strength),
        sep1(',', $.pull_gate_instance)
      )
    ),
    ';'
  ),

  cmos_switch_instance: $ => seq(
    optional($.name_of_instance),
    '(',
    $.output_terminal, ',',
    $.input_terminal, ',',
    $.ncontrol_terminal, ',',
    $.pcontrol_terminal,
    ')'
  ),

  enable_gate_instance: $ => seq(
    optional($.name_of_instance),
    '(', $.output_terminal, ',', $.input_terminal, ',', $.enable_terminal, ')'
  ),

  mos_switch_instance: $ => seq(
    optional($.name_of_instance),
    '(', $.output_terminal, ',', $.input_terminal, ',', $.enable_terminal, ')'
  ),

  n_input_gate_instance: $ => seq(
    optional($.name_of_instance),
    '(', $.output_terminal, ',', sep1(',', $.input_terminal), ')'
  ),

  n_output_gate_instance: $ => seq(
    optional($.name_of_instance),
    '(', sep1(',', $.output_terminal), ',', $.input_terminal, ')'
  ),

  pass_switch_instance: $ => seq(
    optional($.name_of_instance),
    '(', $.inout_terminal, ',', $.inout_terminal, ')'
  ),

  pass_enable_switch_instance: $ => seq(
    optional($.name_of_instance),
    '(', $.inout_terminal, ',', $.inout_terminal, ',', $.enable_terminal, ')'
  ),

  pull_gate_instance: $ => seq(
    optional($.name_of_instance),
    '(', $.output_terminal, ')'
  ),

  // A.3.2 Primitive strengths

  pulldown_strength: $ => choice(
    seq('(', $.strength0, ',', $.strength1, ')'),
    seq('(', $.strength1, ',', $.strength0, ')'),
    seq('(', $.strength0, ')')
  ),

  pullup_strength: $ =>choice(
    seq(',', $.strength0, ',', $.strength1, ')'),
    seq(',', $.strength1, ',', $.strength0, ')'),
    seq(',', $.strength1, ')')
  ),

  // A.3.3 Primitive terminals

  enable_terminal: $ => $.expression,
  inout_terminal: $ => $.net_lvalue,
  input_terminal: $ => $.expression,
  ncontrol_terminal: $ => $.expression,
  output_terminal: $ => $.net_lvalue,
  pcontrol_terminal: $ => $.expression,

  // A.3.4 Primitive gate and switch types

  cmos_switchtype: $ => choice('cmos', 'rcmos'),
  enable_gatetype: $ => choice('bufif0', 'bufif1', 'notif0', 'notif1'),
  mos_switchtype: $ => choice('nmos', 'pmos', 'rnmos', 'rpmos'),
  n_input_gatetype: $ => choice('and', 'nand', 'or', 'nor', 'xor', 'xnor'),
  n_output_gatetype: $ => choice('buf', 'not'),
  pass_en_switchtype: $ => choice('tranif0', 'tranif1', 'rtranif1', 'rtranif0'),
  pass_switchtype: $ => choice('tran', 'rtran'),

  // A.4 Instantiations

  // A.4.1 Instantiation

  // A.4.1.1 Module instantiation

  module_instantiation: $ => seq(
    $._module_identifier,
    optional($.parameter_value_assignment),
    sep1(',', $.hierarchical_instance),
    ';'
  ),

  parameter_value_assignment: $ => seq(
    '#', '(', optional($.list_of_parameter_assignments), ')'
  ),

  list_of_parameter_assignments: $ => choice(
    sep1(',', $.ordered_parameter_assignment),
    sep1(',', $.named_parameter_assignment)
  ),

  ordered_parameter_assignment: $ => alias($.param_expression, $._ordered_parameter_assignment),

  named_parameter_assignment: $ => seq(
    '.', $.parameter_identifier, '(', optional($.param_expression), ')'
  ),

  hierarchical_instance: $ => seq(
    $.name_of_instance, '(', optional($.list_of_port_connections), ')'
  ),

  name_of_instance: $ => seq(
    $.instance_identifier, repeat($.unpacked_dimension)
  ),

  // Reordered

  list_of_port_connections: $ => choice(
    sep1(',', $.named_port_connection),
    sep1(',', $.ordered_port_connection)
  ),

  ordered_port_connection: $ => seq(
    repeat($.attribute_instance),
    $.expression
  ),

  // from spec:
  // named_port_connection: $ =>
  //   { attribute_instance } . port_identifier [ ( [ expression ] ) ]
  // | { attribute_instance } .*

  named_port_connection: $ => seq(
    repeat($.attribute_instance),
    choice(
      seq('.', $.port_identifier, optseq(
        '(', optional($.expression), ')'
      )),
      '.*'
    )
  ),

  /* A.4.1.2 Interface instantiation */

  interface_instantiation: $ => seq(
    $.interface_identifier,
    optional($.parameter_value_assignment),
    sep1(',', $.hierarchical_instance),
    ';'
  ),

  /* A.4.1.3 Program instantiation */

  program_instantiation: $ => seq(
    $.program_identifier,
    optional($.parameter_value_assignment),
    sep1(',', $.hierarchical_instance),
    ';'
  ),

  /* A.4.1.4 Checker instantiation */

  checker_instantiation: $ => seq(
    $.ps_checker_identifier,
    $.name_of_instance,
    '(',
    // optional($.list_of_checker_port_connections),
    choice(
      sep1(',', optseq(
        repeat($.attribute_instance),
        optional($._property_actual_arg)
      )),
      // sep1(',', $.named_checker_port_connection)
      sep1(',', choice(
        seq(
          repeat($.attribute_instance), '.', $.formal_port_identifier,
          optseq('(', optional($._property_actual_arg), ')')
        ),
        seq(
          repeat($.attribute_instance), '.*'
        )
      ))
    ),
    ')',
    ';'
  ),

  // list_of_checker_port_connections1: $ => choice(
  //   sep1(',', optional($.ordered_checker_port_connection1)),
  //   sep1(',', $.named_checker_port_connection)
  // ),

  // ordered_checker_port_connection: $ => seq(
  //   repeat($.attribute_instance),
  //   optional($._property_actual_arg)
  // ),

  // named_checker_port_connection: $ => choice(
  //   seq(
  //     repeat($.attribute_instance), '.', $.formal_port_identifier,
  //     optseq('(', optional($._property_actual_arg), ')')
  //   ),
  //   seq(
  //     repeat($.attribute_instance, '.*')
  //   )
  // ),

  /* A.4.2 Generated instantiation */

  generate_region: $ => seq(
    'generate', repeat($._generate_item), 'endgenerate'
  ),

  loop_generate_construct: $ => seq(
    'for', '(',
    $.genvar_initialization, ';', $._genvar_expression, ';', $.genvar_iteration,
    ')',
    $.generate_block
  ),

  genvar_initialization: $ => seq(
    optional('genvar'),
    $.genvar_identifier,
    '=',
    $.constant_expression
  ),

  genvar_iteration: $ => choice(
    seq($.genvar_identifier, $.assignment_operator, $._genvar_expression),
    seq($.inc_or_dec_operator, $.genvar_identifier),
    seq($.genvar_identifier, $.inc_or_dec_operator)
  ),

  _conditional_generate_construct: $ => choice(
    $.if_generate_construct,
    $.case_generate_construct
  ),

  if_generate_construct: $ => prec.left(seq(
    'if', '(', $.constant_expression, ')', $.generate_block,
    optseq('else', $.generate_block)
  )),

  case_generate_construct: $ => seq(
    'case', '(', $.constant_expression, ')', $.case_generate_item,
    repeat($.case_generate_item),
    'endcase'
  ),

  case_generate_item: $ => choice(
    seq(sep1(',', $.constant_expression), ':', $.generate_block),
    seq('default', optional(':'), $.generate_block)
  ),

  generate_block: $ => choice(
    $._generate_item,
    seq(
      optseq($.generate_block_identifier, ':'),
      'begin',
      optseq(':', $.generate_block_identifier),
      repeat($._generate_item),
      'end',
      optseq(':', $.generate_block_identifier)
    )
  ),

  _generate_item: $ => choice(
    $.module_or_generate_item,
    $.interface_or_generate_item,
    $._checker_or_generate_item
  ),

  /* A.5 UDP declaration and instantiation */

  /* A.5.1 UDP declaration */

  udp_nonansi_declaration: $ => seq(
    repeat($.attribute_instance), 'primitive', $._udp_identifier, '(', $.udp_port_list, ')', ';'
  ),

  udp_ansi_declaration: $ => seq(
    repeat($.attribute_instance), 'primitive', $._udp_identifier, '(', $.udp_declaration_port_list, ')', ';'
  ),

  udp_declaration: $ => choice(
    seq(
      $.udp_nonansi_declaration, $.udp_port_declaration, repeat($.udp_port_declaration),
      $._udp_body,
      'endprimitive', optseq(':', $._udp_identifier)
    ),
    seq($.udp_ansi_declaration, $._udp_body, 'endprimitive', optseq(':', $._udp_identifier)),
    seq('extern', $.udp_nonansi_declaration),
    seq('extern', $.udp_ansi_declaration),
    seq(
      repeat($.attribute_instance), 'primitive', $._udp_identifier, '(', '.*', ')', ';',
      repeat($.udp_port_declaration),
      $._udp_body,
      'endprimitive', optseq(':', $._udp_identifier)
    )
  ),

  /* A.5.2 UDP ports */

  udp_port_list: $ => seq(
    $.output_port_identifier, ',', sep1(',', $.input_port_identifier)
  ),

  udp_declaration_port_list: $ => seq(
    $.udp_output_declaration, ',', sep1(',', $.udp_input_declaration)
  ),

  udp_port_declaration: $ => seq(
    choice(
      $.udp_output_declaration,
      $.udp_input_declaration,
      $.udp_reg_declaration
    ),
    ';'
  ),

  udp_output_declaration: $ => seq(
    repeat($.attribute_instance),
    'output',
    choice(
      $.port_identifier,
      seq('reg', $.port_identifier, optseq('=', $.constant_expression))
    )
  ),

  udp_input_declaration: $ => seq(
    repeat($.attribute_instance), 'input', $.list_of_udp_port_identifiers
  ),

  udp_reg_declaration: $ => seq(
    repeat($.attribute_instance), 'reg', $._variable_identifier
  ),

  /* A.5.3 UDP body */

  _udp_body: $ => choice($.combinational_body, $.sequential_body),

  combinational_body: $ => seq(
    'table', repeat1($.combinational_entry), 'endtable'
  ),

  combinational_entry: $ => seq($.level_input_list, ':', $.output_symbol, ';'),

  sequential_body: $ => seq(
    optional($.udp_initial_statement),
    'table', repeat1($.sequential_entry), 'endtable'
  ),

  udp_initial_statement: $ => seq(
    'initial', $.output_port_identifier, '=', $.init_val, ';'
  ),

  init_val: $ => choice(
    "1'b0", "1'b1", "1'bx", "1'bX", "1'B0", "1'B1", "1'Bx", "1'BX", "1", "0"
  ),

  sequential_entry: $ => seq(
    $._seq_input_list, ':', $._current_state, ':', $.next_state, ';'
  ),

  _seq_input_list: $ => choice($.level_input_list, $.edge_input_list),

  level_input_list: $ => repeat1($.level_symbol),

  edge_input_list: $ => seq(repeat($.level_symbol), $.edge_indicator, repeat($.level_symbol)),

  edge_indicator: $ => choice(
    seq('(', $.level_symbol, $.level_symbol, ')'),
    $.edge_symbol
  ),

  _current_state: $ => $.level_symbol,

  next_state: $ => choice($.output_symbol, '-'),

  output_symbol: $ => /[01xX]/,

  level_symbol: $ => /[01xX?bB]/,

  edge_symbol: $ => /[rRfFpPnN*]/,

  /* A.5.4 UDP instantiation */

  udp_instantiation: $ => seq(
    $._udp_identifier,
    optional($.drive_strength),
    optional($.delay2),
    sep1(',', $.udp_instance),
    ';'
  ),

  udp_instance: $ => seq(
    optional($.name_of_instance),
    '(', $.output_terminal, ',', sep1(',', $.input_terminal), ')'
  ),

  // A.6 Behavioral statements

  // A.6.1 Continuous assignment and net alias statements

  continuous_assign: $ => seq(
    'assign',
    choice(
      seq(
        optional($.drive_strength),
        optional($.delay3),
        $.list_of_net_assignments
      ),
      seq(
        optional($.delay_control),
        $.list_of_variable_assignments
      )
    ),
    ';'
  ),

  list_of_net_assignments: $ => sep1(',', $.net_assignment),

  list_of_variable_assignments: $ => sep1(',', $.variable_assignment),

  net_alias: $ => prec.left(PREC.ASSIGN, seq(
    'alias', $.net_lvalue, '=', sep1(',', seq('=', $.net_lvalue)), ';'
  )),

  net_assignment: $ => prec.left(PREC.ASSIGN,
    seq($.net_lvalue, '=', $.expression)
  ),

  // A.6.2 Procedural blocks and assignments

  initial_construct: $ => seq('initial', $.statement_or_null),

  always_construct: $ => seq($.always_keyword, $.statement),

  always_keyword: $ => choice(
    'always', 'always_comb', 'always_latch', 'always_ff'
  ),

  final_construct: $ => seq('final', $.function_statement),

  blocking_assignment: $ => choice(
    prec.left(PREC.ASSIGN, seq(
      $.variable_lvalue, '=', $.delay_or_event_control, $.expression
    )),
    prec.left(PREC.ASSIGN, seq(
      $.nonrange_variable_lvalue, '=', $.dynamic_array_new
    )),
    // seq(
    //   optional(choice(
    //     seq($.implicit_class_handle, '.'),
    //     $.class_scope,
    //     $.package_scope
    //   )),
    //   $._hierarchical_variable_identifier
    //   $.select,
    //   '=',
    //   $.class_new
    // ),
    $.operator_assignment
  ),

  operator_assignment: $ => prec.left(PREC.ASSIGN,
    seq($.variable_lvalue, $.assignment_operator, $.expression)
  ),

  assignment_operator: $ => choice(
    '=', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<=', '>>=', '<<<=', '>>>='
  ),

  nonblocking_assignment: $ => prec.left(PREC.ASSIGN, seq(
    $.variable_lvalue,
    '<=',
    optional($.delay_or_event_control),
    $.expression
  )),

  procedural_continuous_assignment: $ => choice(
    seq('assign', $.variable_assignment),
    seq('deassign', $.variable_lvalue),
    seq('force', $.variable_assignment),
    seq('force', $.net_assignment),
    seq('release', $.variable_lvalue),
    seq('release', $.net_lvalue)
  ),

  variable_assignment: $ => prec.left(PREC.ASSIGN, seq(
    $.variable_lvalue,
    '=',
    $.expression
  )),

  // A.6.3 Parallel and sequential blocks

  action_block: $ => choice(
    $.statement_or_null,
    seq(optional($.statement), 'else', $.statement_or_null)
  ),

  seq_block: $ => seq(
    'begin', optseq(':', $._block_identifier),
    repeat($.block_item_declaration),
    repeat($.statement_or_null),
    'end', optseq(':', $._block_identifier)
  ),

  par_block: $ => seq(
    'fork', optseq(':', $._block_identifier),
    repeat($.block_item_declaration),
    repeat($.statement_or_null),
    $.join_keyword, optseq(':', $._block_identifier)
  ),

  join_keyword: $ => choice('join', 'join_any', 'join_none'),

  // A.6.4 Statements

  statement_or_null: $ => choice(
    $.statement,
    seq(repeat($.attribute_instance), ';')
  ),

  statement: $ => seq(
    optseq($._block_identifier, ':'),
    repeat($.attribute_instance),
    $.statement_item
  ),

  statement_item: $ => choice(
    seq($.blocking_assignment, ';'),
    seq($.nonblocking_assignment, ';'),
    seq($.procedural_continuous_assignment, ';'),
    seq($.system_tf_call, ';'),
    $.case_statement,
    $.conditional_statement,
    seq($.inc_or_dec_expression, ';'),
    // $.subroutine_call_statement,
    $.disable_statement,
    $.event_trigger,
    $.loop_statement,
    $.jump_statement,
    $.par_block,
    $.seq_block,
    $.procedural_timing_control_statement,
    $.wait_statement,
    $._procedural_assertion_statement,
    seq($.clocking_drive, ';'),
    // $.randsequence_statement,
    $.randcase_statement,
    $.expect_property_statement
  ),

  function_statement: $ => $.statement,

  function_statement_or_null: $ => choice(
    $.function_statement,
    seq(repeat($.attribute_instance), ';')
  ),

  variable_identifier_list: $ => sep1(',', $._variable_identifier),


  // A.6.5 Timing control statements

  procedural_timing_control_statement: $ => seq(
    $._procedural_timing_control, $.statement_or_null // statement_or_null1
  ),

  delay_or_event_control: $ => choice(
    $.delay_control,
    $.event_control,
    seq('repeat', '(', $.expression, ')', $.event_control)
  ),

  delay_control: $ => seq('#', choice(
    $.delay_value,
    seq('(', $.mintypmax_expression, ')')
  )),

  event_control: $ => choice(
    seq('@', $._hierarchical_event_identifier),
    seq('@', '(', $.event_expression, ')'),
    '@*',
    seq('@', '(', '*', ')'),
    seq('@', $.ps_or_hierarchical_sequence_identifier)
  ),

  event_expression: $ => choice( // reordered : brake recursion
    prec.left(seq($.event_expression, 'or', $.event_expression)),
    prec.left(seq($.event_expression, ',', $.event_expression)),
    seq(
      optional($.edge_identifier),
      $.expression
    ) // reordered : help parser
    // seq(
    //   optional($.edge_identifier),
    //   $.expression,
    //   optseq('iff', $.expression)
    // ),
    // seq(
    //   $.sequence_instance,
    //   optseq('iff', $.expression)
    // ),
    // seq('(', $.event_expression, ')')
  ),

  // event_expression_2: $ => choice( // reordered : help parser
  //   seq($.edge_identifier, $.expression), // reordered : help parser
  //   seq(
  //     optional($.edge_identifier),
  //     $.expression,
  //     optseq('iff', $.expression)
  //   ),
  //   // seq(
  //   //   $.sequence_instance,
  //   //   optseq('iff', $.expression)
  //   // ),
  //   seq('(', $.event_expression, ')')
  // ),

  _procedural_timing_control: $ => choice(
    $.delay_control,
    $.event_control,
    $.cycle_delay
  ),

  jump_statement: $ => choice(
    seq('return', optional($.expression), ';'),
    seq('break', ';'),
    seq('continue', ';')
  ),

  wait_statement: $ => choice(
    seq('wait', '(', $.expression, ')', $.statement_or_null),
    seq('wait', 'fork', ';'),
    seq('wait_order', '(', sep1(',', $.hierarchical_identifier), ')', $.action_block)
  ),

  event_trigger: $ => choice(
    seq('->', $._hierarchical_event_identifier, ';'),
    seq('->>', optional($.delay_or_event_control), $._hierarchical_event_identifier, ';')
  ),

  disable_statement: $ => choice(
    seq('disable', $._hierarchical_task_identifier, ';'),
    seq('disable', $._hierarchical_block_identifier, ';'),
    seq('disable', 'fork', ';')
  ),

  // A.6.6 Conditional statements

  conditional_statement: $ => prec.left(seq(
    optional($.unique_priority),
    'if', '(', $.cond_predicate, ')', $.statement_or_null,
    // repseq('else', 'if', '(', $.cond_predicate, ')', $.statement_or_null),
    optseq('else', $.statement_or_null)
  )),

  unique_priority: $ => choice('unique', 'unique0', 'priority'),

  cond_predicate: $ => psep1(PREC.PARENT, '&&&', $._expression_or_cond_pattern), // FIXME precedence

  _expression_or_cond_pattern: $ => choice(
    $.expression,
    $.cond_pattern
  ),

  cond_pattern: $ => prec.left(PREC.MATCHES, seq($.expression, 'matches', $.pattern)),

  // A.6.7 Case statements

  case_statement: $ => seq(
    optional($.unique_priority),
    seq(
      $.case_keyword,
      '(', $.case_expression, ')',
      choice(
        repeat1($.case_item),
        seq('matches', repeat1($.case_pattern_item)),
        seq('inside', repeat1($.case_inside_item)) // only case
      )
    ),
    'endcase'
  ),

  case_keyword: $ => choice('case', 'casez', 'casex'),

  case_expression: $ => $.expression,

  case_item: $ => choice(
    seq(sep1(',', $.case_item_expression), ':', $.statement_or_null),
    seq('default', optional(':'), $.statement_or_null)
  ),

  case_pattern_item: $ => choice(
    seq($.pattern, optseq('&&&', $.expression), ':', $.statement_or_null),
    seq('default', optional(':'), $.statement_or_null)
  ),

  case_inside_item: $ => choice(
    seq($.open_range_list, ':', $.statement_or_null),
    seq('default', optional(':'), $.statement_or_null)
  ),

  case_item_expression: $ => $.expression,

  randcase_statement: $ => seq(
    'randcase', $.randcase_item, repeat($.randcase_item), 'endcase'
  ),

  randcase_item: $ => seq($.expression, ':', $.statement_or_null),

  open_range_list: $ => sep1(',', $.open_value_range),

  open_value_range: $ => $.value_range,

  // A.6.7.1 Patterns

  pattern: $ => choice(
    seq('.', $._variable_identifier),
    '.*',
    $.constant_expression,
    seq('tagged', $.member_identifier, optional($.pattern)),
    seq('\'{', sep1(',', $.pattern), '}'),
    seq('\'{', sep1(',', seq($.member_identifier, ':', $.pattern)), '}')
  ),

  assignment_pattern: $ => seq(
    '\'{',
    choice(
      sep1(',', $.expression),
      // sep1(',', seq($._structure_pattern_key, ':', $.expression)),
      sep1(',', seq($._array_pattern_key, ':', $.expression)),
      seq($.constant_expression, '{', sep1(',', $.expression), '}')
    ),
    '}'
  ),

  _structure_pattern_key: $ => choice(
    $.member_identifier,
    $.assignment_pattern_key
  ),

  _array_pattern_key: $ => choice(
    $.constant_expression,
    $.assignment_pattern_key
  ),

  assignment_pattern_key: $ => choice(
    $._simple_type,
    'default'
  ),

  assignment_pattern_expression: $ => seq(
    optional($._assignment_pattern_expression_type), $.assignment_pattern
  ),

  _assignment_pattern_expression_type: $ => choice(
    $.ps_type_identifier,
    // $.ps_parameter_identifier,
    $.integer_atom_type,
    $.type_reference
  ),

  constant_assignment_pattern_expression: $ => $.assignment_pattern_expression,

  assignment_pattern_net_lvalue: $ => seq(
    '\'{', sep1(',', $.net_lvalue), '}'
  ),

  assignment_pattern_variable_lvalue: $ => seq(
    '\'{', sep1(',', $.variable_lvalue), '}'
  ),

  // A.6.8 Looping statements

  loop_statement: $ => choice(
    seq('forever', $.statement_or_null),
    seq('repeat', '(', $.expression, ')', $.statement_or_null),
    seq('while', '(', $.expression, ')', $.statement_or_null),
    seq(
      'for', '(',
      optional($.for_initialization), ';',
      optional($.expression), ';',
      optional($.for_step),
      ')',
      $.statement_or_null
    ),
    seq('do', $.statement_or_null, 'while', '(', $.expression, ')', ';'),
    seq(
      'foreach', '(',
      $.ps_or_hierarchical_array_identifier,
      '[',
      optional($.loop_variables1),
      ']',
      ')',
      $.statement
    )
  ),

  for_initialization: $ => choice(
    $.list_of_variable_assignments,
    sep1(',', $.for_variable_declaration)
  ),

  for_variable_declaration: $ => seq(
    optional('var'), $.data_type,
    sep1(',', seq(
      $._variable_identifier, '=', $.expression
    ))
  ),

  for_step: $ => sep1(',', $._for_step_assignment),

  _for_step_assignment: $ => choice(
    $.operator_assignment,
    $.inc_or_dec_expression,
    $.function_subroutine_call
  ),

  loop_variables1: $ => seq(
    $.index_variable_identifier,
    repseq(',', optional($.index_variable_identifier))
  ),

  // A.6.9 Subroutine call statements

  subroutine_call_statement: $ => choice(
    seq($.subroutine_call, ';'),
    seq('void\'', '(', $.function_subroutine_call, ')', ';')
  ),

  // A.6.10 Assertion statements

  _assertion_item: $ => choice(
    $.concurrent_assertion_item,
    $.deferred_immediate_assertion_item
  ),

  deferred_immediate_assertion_item: $ => seq(
    optseq(
      $._block_identifier, ':'
    ),
    $._deferred_immediate_assertion_statement
  ),

  _procedural_assertion_statement: $ => choice(
    $._concurrent_assertion_statement,
    $._immediate_assertion_statement,
    $.checker_instantiation
  ),

  _immediate_assertion_statement: $ => choice(
    $._simple_immediate_assertion_statement,
    $._deferred_immediate_assertion_statement
  ),

  _simple_immediate_assertion_statement: $ => choice(
    $.simple_immediate_assert_statement,
    $.simple_immediate_assume_statement,
    $.simple_immediate_cover_statement
  ),

  simple_immediate_assert_statement: $ => seq(
    'assert', '(', $.expression, ')', $.action_block
  ),

  simple_immediate_assume_statement: $ => seq(
    'assume', '(', $.expression, ')', $.action_block
  ),

  simple_immediate_cover_statement: $ => seq(
    'cover', '(', $.expression, ')', $.statement_or_null
  ),

  _deferred_immediate_assertion_statement: $ => choice(
    $.deferred_immediate_assert_statement,
    $.deferred_immediate_assume_statement,
    $.deferred_immediate_cover_statement
  ),

  deferred_immediate_assert_statement: $ => seq(
    'assert',
    choice('#0', 'final'),
    '(', $.expression, ')', $.action_block
  ),

  deferred_immediate_assume_statement: $ => seq(
    'assume',
    choice('#0', 'final'),
    '(', $.expression, ')', $.action_block
  ),

  deferred_immediate_cover_statement: $ => seq(
    'cover',
    choice('#0', 'final'),
    '(', $.expression, ')', $.statement_or_null
  ),

  /* A.6.11 Clocking block */

  clocking_declaration: $ => choice(
    seq(
      optional('default'),
      'clocking', optional($.clocking_identifier), $.clocking_event, ';',
      repeat($.clocking_item),
      'endclocking', optseq(':', $.clocking_identifier)
    ),
    seq(
      'global',
      'clocking', optional($.clocking_identifier), $.clocking_event, ';',
      'endclocking', optseq(':', $.clocking_identifier)
    )
  ),

  clocking_event: $ => seq('@', choice(
    $._identifier,
    seq('(', $.event_expression, ')')
  )),

  clocking_item: $ => choice(
    seq('default', $.default_skew, ';'),
    seq($.clocking_direction, $.list_of_clocking_decl_assign, ';'),
    seq(repeat($.attribute_instance), $._assertion_item_declaration)
  ),

  default_skew: $ => choice(
    seq('input', $.clocking_skew),
    seq('output', $.clocking_skew),
    seq('input', $.clocking_skew, 'output', $.clocking_skew)
  ),

  clocking_direction: $ => choice(
    seq('input', optional($.clocking_skew)),
    seq('output', optional($.clocking_skew)),
    seq('input', optional($.clocking_skew), 'output', optional($.clocking_skew)),
    seq('inout')
  ),

  list_of_clocking_decl_assign: $ => sep1(',', $.clocking_decl_assign),

  clocking_decl_assign: $ => seq($._signal_identifier, optseq('=', $.expression)),

  clocking_skew: $ => choice(
    seq($.edge_identifier, optional($.delay_control)),
    $.delay_control
  ),

  clocking_drive: $ => prec.left(PREC.ASSIGN,
    seq($.clockvar_expression, '<=', optional($.cycle_delay), $.expression)
  ),

  cycle_delay: $ => prec.left(seq('##', choice(
    $.integral_number,
    $._identifier,
    seq('(', $.expression, ')')
  ))),

  clockvar: $ => $.hierarchical_identifier,

  clockvar_expression: $ => seq(
    $.clockvar,
    optional($.select1)
  ),

  // A.6.12 Randsequence

  // randsequence_statement = randsequence ( [ production_identifier ] )
  // production { production }
  // endsequence
  // production
  //   = [ data_type_or_void ] production_identifier
  //  [ ( tf_port_list ) ] : rs_rule { | rs_rule } ;
  // rs_rule = rs_production_list [ := weight_specification [ rs_code_block ] ]
  // rs_production_list =
  // rs_prod { rs_prod }
  // | rand join [ ( expression ) ] production_item
  //   production_item { production_item }
  // weight_specification =
  // integral_number
  // | ps_identifier
  // | ( expression )
  // rs_code_block = { { data_declaration } { statement_or_null } }
  // rs_prod =
  // production_item
  // | rs_code_block
  // | rs_if_else
  // | rs_repeat
  // | rs_case
  // production_item = production_identifier [ ( list_of_arguments ) ]
  // rs_if_else = if ( expression ) production_item [ else production_item ]
  // rs_repeat = repeat ( expression ) production_item
  // rs_case = case ( case_expression ) rs_case_item { rs_case_item } endcase
  // rs_case_item =
  // case_item_expression { , case_item_expression } : production_item ;
  // | default [ : ] production_item ;

  // A.7 Specify section

  // A.7.1 Specify block declaration

  specify_block: $ => seq('specify', repeat($._specify_item), 'endspecify'),

  _specify_item: $ => choice(
    $.specparam_declaration,
    $.pulsestyle_declaration,
    $.showcancelled_declaration,
    $.path_declaration,
    $._system_timing_check
  ),

  pulsestyle_declaration: $ => seq(
    choice('pulsestyle_onevent', 'pulsestyle_ondetect'),
    $.list_of_path_outputs,
    ';'
  ),

  showcancelled_declaration: $ => seq(
    choice('showcancelled', 'noshowcancelled'),
    $.list_of_path_outputs,
    ';'
  ),

  // A.7 Specify section

  // A.7.1 Specify block declaration

  // A.7.2 Specify path declarations

  path_declaration: $ => seq(
    choice(
      $.simple_path_declaration,
      $.edge_sensitive_path_declaration,
      $.state_dependent_path_declaration
    ),
    ';'
  ),

  simple_path_declaration: $ => seq(
    choice($.parallel_path_description, $.full_path_description),
    '=',
    $.path_delay_value
  ),

  parallel_path_description: $ => seq(
    '(',
    $.specify_input_terminal_descriptor,
    optional($.polarity_operator),
    '=>',
    $.specify_output_terminal_descriptor,
    ')'
  ),

  full_path_description: $ => seq(
    '(',
    $.list_of_path_inputs,
    optional($.polarity_operator),
    '*>',
    $.list_of_path_outputs,
    ')'
  ),

  list_of_path_inputs: $ => sep1(',', $.specify_input_terminal_descriptor),

  list_of_path_outputs: $ => sep1(',', $.specify_output_terminal_descriptor),

  // A.7.3 Specify block terminals

  specify_input_terminal_descriptor: $ => seq(
    $.input_identifier, optseq('[', $._constant_range_expression, ']')
  ),

  specify_output_terminal_descriptor: $ => seq(
    $.output_identifier, optseq('[', $._constant_range_expression, ']')
  ),

  input_identifier: $ => choice(
    $.input_port_identifier,
    $.inout_port_identifier,
    seq($.interface_identifier, '.', $.port_identifier) // FIXME glue dot?
  ),

  output_identifier: $ => choice(
    $.output_port_identifier,
    $.inout_port_identifier,
    seq($.interface_identifier, '.', $.port_identifier)
  ),

  /* A.7.4 Specify path delays */

  path_delay_value: $ => choice(
    $.list_of_path_delay_expressions,
    seq('(', $.list_of_path_delay_expressions, ')')
  ),

  list_of_path_delay_expressions: $ => sep1(',', $.path_delay_expression),

  // list_of_path_delay_expressions: $ => choice(
  //   $.t_path_delay_expression,
  //   seq($.trise_path_delay_expression, ',', $.tfall_path_delay_expression),
  //   seq(
  //     $.trise_path_delay_expression, ',', $.tfall_path_delay_expression, ',',
  //     $.tz_path_delay_expression
  //   ),
  //   seq(
  //     $.t01_path_delay_expression, ',', $.t10_path_delay_expression, ',',
  //     $.t0z_path_delay_expression, ',', $.tz1_path_delay_expression, ',',
  //     $.t1z_path_delay_expression, ',', $.tz0_path_delay_expression
  //   ),
  //   seq(
  //     $.t01_path_delay_expression, ',', $.t10_path_delay_expression, ',',
  //     $.t0z_path_delay_expression, ',', $.tz1_path_delay_expression, ',',
  //     $.t1z_path_delay_expression, ',', $.tz0_path_delay_expression, ',',
  //     $.t0x_path_delay_expression, ',', $.tx1_path_delay_expression, ',',
  //     $.t1x_path_delay_expression, ',', $.tx0_path_delay_expression, ',',
  //     $.txz_path_delay_expression, ',', $.tzx_path_delay_expression
  //   )
  // ),
  //
  // t_path_delay_expression: $ => alias($.path_delay_expression, $.t_path_delay_expression),
  // trise_path_delay_expression: $ => alias($.path_delay_expression, $.trise_path_delay_expression),
  // tfall_path_delay_expression: $ => alias($.path_delay_expression, $.tfall_path_delay_expression),
  // tz_path_delay_expression: $ => alias($.path_delay_expression, $.tz_path_delay_expression),
  // t01_path_delay_expression: $ => alias($.path_delay_expression, $.t01_path_delay_expression),
  // t10_path_delay_expression: $ => alias($.path_delay_expression, $.t10_path_delay_expression),
  // t0z_path_delay_expression: $ => alias($.path_delay_expression, $.t0z_path_delay_expression),
  // tz1_path_delay_expression: $ => alias($.path_delay_expression, $.tz1_path_delay_expression),
  // t1z_path_delay_expression: $ => alias($.path_delay_expression, $.t1z_path_delay_expression),
  // tz0_path_delay_expression: $ => alias($.path_delay_expression, $.tz0_path_delay_expression),
  // t0x_path_delay_expression: $ => alias($.path_delay_expression, $.t0x_path_delay_expression),
  // tx1_path_delay_expression: $ => alias($.path_delay_expression, $.tx1_path_delay_expression),
  // t1x_path_delay_expression: $ => alias($.path_delay_expression, $.t1x_path_delay_expression),
  // tx0_path_delay_expression: $ => alias($.path_delay_expression, $.tx0_path_delay_expression),
  // txz_path_delay_expression: $ => alias($.path_delay_expression, $.txz_path_delay_expression),
  // tzx_path_delay_expression: $ => alias($.path_delay_expression, $.tzx_path_delay_expression),

  path_delay_expression: $ => $.constant_mintypmax_expression,

  edge_sensitive_path_declaration: $ => seq(
    choice(
      $.parallel_edge_sensitive_path_description,
      $.full_edge_sensitive_path_description
    ),
    '=', $.path_delay_value
  ),

  parallel_edge_sensitive_path_description: $ => seq(
    '(',
    optional($.edge_identifier),
    $.specify_input_terminal_descriptor,
    optional($.polarity_operator),
    '=>',
    '(',
    $.specify_output_terminal_descriptor,
    optional($.polarity_operator),
    ':',
    $.data_source_expression,
    ')',
    ')'
  ),

  full_edge_sensitive_path_description: $ => seq(
    '(',
    optional($.edge_identifier),
    $.list_of_path_inputs,
    optional($.polarity_operator),
    '*>',
    '(',
    $.list_of_path_outputs,
    optional($.polarity_operator),
    ':',
    $.data_source_expression,
    ')',
    ')'
  ),

  data_source_expression: $ => $.expression,

  edge_identifier: $ => choice('posedge', 'negedge', 'edge'),

  state_dependent_path_declaration: $ => choice(
    seq('if', '(', $.module_path_expression, ')', $.simple_path_declaration),
    seq('if', '(', $.module_path_expression, ')', $.edge_sensitive_path_declaration),
    seq('ifnone', $.simple_path_declaration)
  ),

  polarity_operator: $ => choice('+', '-'),

  /* A.7.5 System timing checks */

  /* A.7.5.1 System timing check commands */

  _system_timing_check: $ => choice(
    $.$setup_timing_check,
    $.$hold_timing_check,
    $.$setuphold_timing_check,
    $.$recovery_timing_check,
    $.$removal_timing_check,
    $.$recrem_timing_check,
    $.$skew_timing_check,
    $.$timeskew_timing_check,
    $.$fullskew_timing_check,
    $.$period_timing_check,
    $.$width_timing_check,
    $.$nochange_timing_check
  ),

  $setup_timing_check: $ => seq(
    '$setup', '(',
    $.data_event, ',', $.reference_event, ',', $.timing_check_limit,
    optseq(',', optional($.notifier)),
    ')', ';'
  ),

  $hold_timing_check: $ => seq(
    '$hold', '(',
    $.reference_event, ',', $.data_event, ',', $.timing_check_limit,
    optseq(',', optional($.notifier)),
    ')', ';'
  ),

  $setuphold_timing_check: $ => seq(
    '$setuphold', '(',
    $.reference_event, ',', $.data_event, ',', $.timing_check_limit, ',', $.timing_check_limit,
    optseq(
      ',',
      optional($.notifier),
      optseq(
        ',',
        optional($.timestamp_condition),
        optseq(
          ',',
          optional($.timecheck_condition),
          optseq(
            ',',
            optional($.delayed_reference),
            optseq(
              ',',
              optional($.delayed_data)
            )
          )
        )
      )
    ),
    ')', ';'
  ),

  $recovery_timing_check: $ => seq(
    '$recovery', '(',
    $.reference_event, ',', $.data_event, ',', $.timing_check_limit,
    optseq(',', optional($.notifier)),
    ')', ';'
  ),

  $removal_timing_check: $ => seq(
    '$removal', '(',
    $.reference_event, ',', $.data_event, ',', $.timing_check_limit,
    optseq(',', optional($.notifier)),
    ')', ';'
  ),

  $recrem_timing_check: $ => seq(
    '$recrem', '(',
    $.reference_event, ',', $.data_event, ',', $.timing_check_limit, ',', $.timing_check_limit,
    optseq(
      ',',
      optional($.notifier),
      optseq(',',
        optional($.timestamp_condition),
        optseq(',', optional($.timecheck_condition)),
        optseq(
          ',',
          optional($.delayed_reference),
          optseq(',', optional($.delayed_data))
        )
      )
    ),
    ')', ';'
  ),

  $skew_timing_check: $ => seq(
    '$skew', '(',
    $.reference_event, ',', $.data_event, ',', $.timing_check_limit,
    optseq(',', optional($.notifier)),
    ')', ';'
  ),

  $timeskew_timing_check: $ => seq(
    '$timeskew', '(',
    $.reference_event, ',', $.data_event, ',', $.timing_check_limit,
    optseq(',',
      optional($.notifier),
      optseq(',',
        optional($.event_based_flag),
        optseq(',', optional($.remain_active_flag))
      )
    ),
    ')', ';'
  ),

  $fullskew_timing_check: $ => seq(
    '$fullskew', '(',
    $.reference_event, ',', $.data_event, ',', $.timing_check_limit, ',', $.timing_check_limit,
    optseq(',',
      optional($.notifier),
      optseq(',',
        optional($.event_based_flag),
        optseq(',', optional($.remain_active_flag))
      )
    ),
    ')', ';'
  ),

  $period_timing_check: $ => seq(
    '$period', '(', $.controlled_reference_event, ',', $.timing_check_limit,
    optseq(',', optional($.notifier)),
    ')', ';'
  ),

  $width_timing_check: $ => seq(
    '$width', '(',
    $.controlled_reference_event, ',', $.timing_check_limit, ',', $.threshold,
    optseq(',', optional($.notifier)),
    ')', ';'
  ),

  $nochange_timing_check: $ => seq(
    '$nochange', '(',
    $.reference_event, ',', $.data_event, ',', $.start_edge_offset, ',', $.end_edge_offset,
    optseq(',', optional($.notifier)),
    ')', ';'
  ),

  // A.7.5.2 System timing check command arguments

  timecheck_condition: $ => $.mintypmax_expression,

  controlled_reference_event: $ => alias($.controlled_timing_check_event, $.controlled_reference_event),

  data_event: $ => $.timing_check_event,

  delayed_data: $ => seq(
    $.terminal_identifier, optional($.constant_mintypmax_expression)
  ),

  delayed_reference: $ => seq(
    $.terminal_identifier, optional($.constant_mintypmax_expression)
  ),

  end_edge_offset: $ => $.mintypmax_expression,

  event_based_flag: $ => $.constant_expression,

  notifier: $ => $._variable_identifier,

  reference_event: $ => $.timing_check_event,

  remain_active_flag: $ => $.constant_mintypmax_expression,

  timestamp_condition: $ => $.mintypmax_expression,

  start_edge_offset: $ => $.mintypmax_expression,

  threshold: $ => $.constant_expression,

  timing_check_limit: $ => $.expression,

  // A.7.5.3 System timing check event definitions

  timing_check_event: $ => seq(
    optional($.timing_check_event_control),
    $._specify_terminal_descriptor,
    optseq('&&&', $.timing_check_condition)
  ),

  controlled_timing_check_event: $ => seq(
    $.timing_check_event_control,
    $._specify_terminal_descriptor,
    optseq('&&&', $.timing_check_condition)
  ),

  timing_check_event_control: $ => choice(
    'posedge', 'negedge', 'edge', $.edge_control_specifier
  ),

  _specify_terminal_descriptor: $ => choice(
    $.specify_input_terminal_descriptor,
    $.specify_output_terminal_descriptor
  ),

  edge_control_specifier: $ => seq(
    'edge', '[', sep1(',', $.edge_descriptor), ']'
  ),

  // Note: Embedded spaces are illegal.
  edge_descriptor: $ => choice(
    '01',
    '10',
    /[xXzZ][01]/,
    /[01][xXzZ]/
  ),

  timing_check_condition: $ => choice(
    $.scalar_timing_check_condition,
    seq('(', $.scalar_timing_check_condition, ')')
  ),

  scalar_timing_check_condition: $ => choice(
    $.expression,
    seq('~', $.expression),
    seq($.expression, '==', $.scalar_constant),
    seq($.expression, '===', $.scalar_constant),
    seq($.expression, '!=', $.scalar_constant),
    seq($.expression, '!==', $.scalar_constant)
  ),

  scalar_constant: $ => choice(
    '1\'b0',
    '1\'b1',
    '1\'B0',
    '1\'B1',
    '\'b0',
    '\'b1',
    '\'B0',
    '\'B1',
    '1',
    '0'
  ),

  // A.8 Expressions

  // A.8.1 Concatenations

  concatenation: $ => seq(
    '{', psep1(PREC.CONCAT, ',', $.expression), '}'
  ),

  constant_concatenation: $ => seq(
    '{', psep1(PREC.CONCAT, ',', $.constant_expression), '}'
  ),

  constant_multiple_concatenation: $ => prec.left(PREC.CONCAT, seq(
    '{', $.constant_expression, $.constant_concatenation, '}'
  )),

  module_path_concatenation: $ => seq(
    '{', psep1(PREC.CONCAT, ',', $.module_path_expression), '}'
  ),

  module_path_multiple_concatenation: $ => prec.left(PREC.CONCAT, seq(
    '{', $.constant_expression, $.module_path_concatenation, '}'
  )),

  multiple_concatenation: $ => prec.left(PREC.CONCAT, seq(
    '{', $.expression, $.concatenation, '}'
  )),

  streaming_concatenation: $ => prec.left(PREC.CONCAT, seq(
    '{', $.stream_operator, optional($.slice_size), $.stream_concatenation, '}'
  )),

  stream_operator: $ => choice('>>', '<<'),

  slice_size: $ => choice($._simple_type, $.constant_expression),

  stream_concatenation: $ => prec.left(PREC.CONCAT, seq(
    '{', sep1(',', $.stream_expression), '}'
  )),

  stream_expression: $ => seq($.expression, optseq('with', '[', $.array_range_expression, ']')),

  array_range_expression: $ => seq(
    $.expression,
    optional(choice(
      seq( ':', $.expression),
      seq('+:', $.expression),
      seq('-:', $.expression)
    ))
  ),

  empty_unpacked_array_concatenation: $ => seq('{', '}'),

  /* A.8.2 Subroutine calls */

  constant_function_call: $ => $.function_subroutine_call,

  tf_call: $ => prec.left(seq(
    $._hierarchical_tf_identifier, // FIXME
    // $.ps_or_hierarchical_tf_identifier,
    repeat($.attribute_instance),
    optional($.list_of_arguments_parent)
  )),

  system_tf_call: $ => prec.left(seq(
    $.system_tf_identifier,
    optional(choice(
      $.list_of_arguments_parent,
      seq(
        '(',
        choice(
          seq($.data_type, optseq(',', $.expression)),
          prec.left(seq(
            sep1(',', $.expression),
            optseq(',', optional($.clocking_event))
          ))
        ),
        ')'
      )
    ))
  )),

  subroutine_call: $ => choice(
    $.tf_call,
    $.system_tf_call,
    $.method_call,
    seq(optseq('std', '::'), $.randomize_call)
  ),

  function_subroutine_call: $ => $.subroutine_call,

  list_of_arguments: $ => choice(
    // seq(
    //   sep1(',', optional($.expression)),
    //   repseq(',', '.', $._identifier, '(', optional($.expression), ')')
    // ),
    sep1(',', seq('.', $._identifier, '(', optional($.expression), ')'))
  ),

  list_of_arguments_parent: $ => seq(
    '(',
    choice(
      sep1(',', $.expression),
      // sep1(',', optional($.expression)), // FIXME
      seq(
        repseq(',', '.', $._identifier, '(', optional($.expression), ')')
      ),
      sep1(',', seq(',', '.', $._identifier, '(', optional($.expression), ')'))
    ),
    ')'
  ),

  method_call: $ => seq($._method_call_root, '.', $.method_call_body),

  method_call_body: $ => choice(
    prec.left(seq(
      $.method_identifier,
      repeat($.attribute_instance),
      optional($.list_of_arguments_parent)
    )),
    $._built_in_method_call
  ),

  _built_in_method_call: $ => choice(
    $.array_manipulation_call,
    $.randomize_call
  ),

  array_manipulation_call: $ => prec.left(seq(
    $.array_method_name,
    repeat($.attribute_instance),
    optional($.list_of_arguments_parent),
    optseq('with', '(', $.expression, ')')
  )),

  randomize_call: $ => prec.left(seq(
    'randomize',
    repeat($.attribute_instance),
    optseq(
      '(',
      optional(choice(
        $.variable_identifier_list,
        'null'
      )),
      ')'
    ),
    optseq(
      'with',
      optseq(
        '(',
        optional($.identifier_list),
        ')'
      ),
      $.constraint_block
    )
  )),

  _method_call_root: $ => choice($.primary, $.implicit_class_handle),

  array_method_name: $ => choice(
    $.method_identifier, 'unique', 'and', 'or', 'xor'
  ),

  // A.8.3 Expressions

  inc_or_dec_expression: $ => choice(
    seq($.inc_or_dec_operator, repeat($.attribute_instance), $.variable_lvalue),
    seq($.variable_lvalue, repeat($.attribute_instance), $.inc_or_dec_operator)
  ),

  conditional_expression: $ => prec.right(PREC.CONDITIONAL, seq(
    $.cond_predicate,
    '?',
    repeat($.attribute_instance), $.expression,
    ':',
    $.expression
  )),

  constant_expression: $ => choice(
    $.constant_primary,

    prec.left(PREC.UNARY, seq(
      $.unary_operator, repeat($.attribute_instance), $.constant_primary
    )),

    constExprOp($, PREC.ADD, choice('+', '-')),
    constExprOp($, PREC.MUL, choice('*', '/', '%')),
    constExprOp($, PREC.EQUAL, choice('==', '!=', '===', '!==', '==?', '!=?')),
    constExprOp($, PREC.LOGICAL_AND, '&&'),
    constExprOp($, PREC.LOGICAL_OR, '||'),
    constExprOp($, PREC.POW, '**'),
    constExprOp($, PREC.RELATIONAL, choice('<', '<=', '>', '>=')),
    constExprOp($, PREC.AND, '&'),
    constExprOp($, PREC.OR, '|'),
    constExprOp($, PREC.XOR, choice('^', '^~', '~^')),
    constExprOp($, PREC.SHIFT, choice('>>', '<<', '>>>', '<<<')),
    constExprOp($, PREC.IMPLICATION, choice('->', '<->')),

    prec.right(PREC.CONDITIONAL, seq(
      $.constant_expression,
      '?',
      repeat($.attribute_instance), $.constant_expression,
      ':',
      $.constant_expression
    ))
  ),

  constant_mintypmax_expression: $ => seq(
    $.constant_expression,
    optseq(':', $.constant_expression, ':', $.constant_expression)
  ),

  constant_param_expression: $ => choice(
    $.constant_mintypmax_expression,
    $.data_type,
    '$'
  ),

  param_expression: $ => choice(
    $.mintypmax_expression,
    $.data_type,
    '$'
  ),

  _constant_range_expression: $ => choice(
    $.constant_expression,
    $._constant_part_select_range
  ),

  _constant_part_select_range: $ => choice(
    $.constant_range,
    $.constant_indexed_range
  ),

  constant_range: $ => seq($.constant_expression, ':', $.constant_expression),

  constant_indexed_range: $ => seq(
    $.constant_expression, choice('+:', '-:'), $.constant_expression
  ),

  expression: $ => choice(
    $.primary,

    prec.left(PREC.UNARY, seq(
      $.unary_operator, repeat($.attribute_instance), $.primary
    )),
    prec.left(PREC.UNARY, $.inc_or_dec_expression),
    prec.left(PREC.PARENT, seq('(', $.operator_assignment, ')')),

    exprOp($, PREC.ADD, choice('+', '-')),
    exprOp($, PREC.MUL, choice('*', '/', '%')),
    exprOp($, PREC.EQUAL, choice('==', '!=', '===', '!==', '==?', '!=?')),
    exprOp($, PREC.LOGICAL_AND, '&&'),
    exprOp($, PREC.LOGICAL_OR, '||'),
    exprOp($, PREC.POW, '**'),
    exprOp($, PREC.RELATIONAL, choice('<', '<=', '>', '>=')),
    exprOp($, PREC.AND, '&'),
    exprOp($, PREC.OR, '|'),
    exprOp($, PREC.XOR, choice('^', '^~', '~^')),
    exprOp($, PREC.SHIFT, choice('>>', '<<', '>>>', '<<<')),
    exprOp($, PREC.IMPLICATION, choice('->', '<->')),

    $.conditional_expression,
    $.inside_expression,
    $.tagged_union_expression
  ),

  tagged_union_expression: $ => prec.left(seq(
    'tagged',
    $.member_identifier,
    optional($.expression)
  )),

  inside_expression: $ => prec.left(PREC.RELATIONAL, seq(
    $.expression, 'inside', '{', $.open_range_list, '}'
  )),

  value_range: $ => choice(
    $.expression,
    seq('[', $.expression, ':', $.expression, ']')
  ),

  mintypmax_expression: $ => seq(
    $.expression,
    optseq(':', $.expression, ':', $.expression)
  ),

  module_path_conditional_expression: $ => seq(
    $.module_path_expression,
    '?',
    repeat($.attribute_instance), $.module_path_expression,
    ':',
    $.module_path_expression
  ),

  module_path_expression: $ => choice(
    $.module_path_primary
    // seq($.unary_module_path_operator, repeat($.attribute_instance), $.module_path_primary),
    // seq(
    //   $.module_path_expression,
    //   $.binary_module_path_operator,
    //   repeat($.attribute_instance),
    //   $.module_path_expression
    // ),
    // $.module_path_conditional_expression
  ),

  module_path_mintypmax_expression: $ => seq(
    $.module_path_expression,
    optseq(
      ':', $.module_path_expression,
      ':', $.module_path_expression
    )
  ),

  _part_select_range: $ => choice(
    $.constant_range,
    $.indexed_range
  ),

  indexed_range: $ => seq(
    $.expression, choice('+:', '-:'), $.constant_expression
  ),

  _genvar_expression: $ => $.constant_expression,

  /* A.8.4 Primaries */



  // FIXME FIXME FIXME

  constant_primary: $ => choice(
    $.primary_literal,
    seq($.ps_parameter_identifier, optional($.constant_select1)),
    // seq($.specparam_identifier, optseq('[', $._constant_range_expression, ']')),
    // $.genvar_identifier,
    // seq($.formal_port_identifier, optional($.constant_select1)),
    // seq(optional(choice($.package_scope, $.class_scope)), $.enum_identifier),
    seq($.constant_concatenation, optseq('[', $._constant_range_expression, ']')),
    seq($.constant_multiple_concatenation, optseq('[', $._constant_range_expression, ']')),
    // $.constant_function_call,
    // $._constant_let_expression,
    seq('(', $.constant_mintypmax_expression, ')'),
    // $.constant_cast,
    // // $.constant_assignment_pattern_expression,
    $.type_reference,
    'null'
  ),

  module_path_primary: $ => choice(
    $._number,
    $._identifier,
    $.module_path_concatenation,
    $.module_path_multiple_concatenation,
    $.function_subroutine_call,
    seq('(', $.module_path_mintypmax_expression, ')')
  ),

  primary: $ => choice(
    $.primary_literal,
    seq(
      optional(choice($.class_qualifier, $.package_scope)),
      $.hierarchical_identifier,
      optional($.select1)
    ),
    $.empty_unpacked_array_concatenation,
    seq($.concatenation, optseq('[', $.range_expression, ']')),
    seq($.multiple_concatenation, optseq('[', $.range_expression, ']')),
    $.function_subroutine_call,
    $.let_expression,
    seq('(', $.mintypmax_expression, ')'),
    $.cast,
    $.assignment_pattern_expression,
    $.streaming_concatenation,
    $.sequence_method_call,
    'this',
    '$',
    'null'
  ),

  class_qualifier: $ => seq(
    optseq('local', '::'),
    choice( // TODO optional?
      seq($.implicit_class_handle, '.'),
      $.class_scope
    )
  ),


  range_expression: $ => choice(
    $.expression,
    $._part_select_range
  ),
  //

  primary_literal: $ => choice(
    $._number,
    $.time_literal,
    $.unbased_unsized_literal,
    $.string_literal,
    $.simple_text_macro_usage
  ),

  time_literal: $ => choice(
    seq($.unsigned_number, $.time_unit),
    seq($.fixed_point_number, $.time_unit)
  ),

  time_unit: $ => choice('s', 'ms', 'us', 'ns', 'ps', 'fs'),

  string_literal: $ => seq(
    '"',
    repeat(choice(
      token.immediate(/[^\\"]+/),
      // EXTENDS Verilog spec with escape sequences
      token.immediate(seq('\\', /./)),
      token.immediate(seq('\\', '\n'))
    )),
    '"'
  ),

  implicit_class_handle: $ => choice(
    prec.left(seq('this', optseq('.', 'super'))),
    'super'
  ),

  bit_select1: $ => prec.left(PREC.PARENT, repeat1(seq( // reordered -> non empty
    '[', $.expression, ']')
  )),

  select1: $ => choice( // reordered -> non empty
    prec.left(PREC.PARENT, seq( // 1xx
      repseq('.', $.member_identifier, optional($.bit_select1)), '.', $.member_identifier,
      optional($.bit_select1),
      optseq('[', $._part_select_range, ']')
    )),
    prec.left(PREC.PARENT, seq( // 01x
      //
      $.bit_select1,
      optseq('[', $._part_select_range, ']')
    )),
    prec.left(PREC.PARENT, seq( // 001
      //
      //
      seq('[', $._part_select_range, ']')
    ))
  ),

  nonrange_select1: $ => choice( // reordered -> non empty
    prec.left(PREC.PARENT, seq( // 1x
      repseq('.', $.member_identifier, optional($.bit_select1)), '.', $.member_identifier,
      optional($.bit_select1)
    )),
    $.bit_select1
  ),

  constant_bit_select1: $ => repeat1(prec.left(PREC.PARENT, seq( // reordered -> non empty
    '[', $.constant_expression, ']'
  ))),

  constant_select1: $ => choice( // reordered -> non empty
    seq(
      '[',
      repseq($.constant_expression, ']', '['),
      choice($.constant_expression, $._constant_part_select_range),
      ']'
    )
  ),

  // constant_select1: $ => choice( // reordered -> non empty
  //   // seq(
  //   //   repseq('.', $.member_identifier, optional($.constant_bit_select1))),
  //   //   '.', $.member_identifier,
  //   //   optional($.constant_bit_select1),
  //   //   optseq('[', $._constant_part_select_range, ']')
  //   // ),
  //   seq(
  //     $.constant_bit_select1,
  //     optseq('[', $._constant_part_select_range, ']')
  //   ),
  //   seq('[', $._constant_part_select_range, ']'),
  // ),

  constant_cast: $ => seq($.casting_type, '\'', '(', $.constant_expression, ')'),

  _constant_let_expression: $ => $.let_expression,

  cast: $ => seq($.casting_type, '\'', '(', $.expression, ')'),

  // A.8.5 Expression left-side values

  net_lvalue: $ => choice(
    seq(
      $.ps_or_hierarchical_net_identifier,
      optional($.constant_select1)
    ),
    prec.left(PREC.CONCAT, seq('{', sep1(',', $.net_lvalue), '}')),
    seq(
      optional($._assignment_pattern_expression_type),
      $.assignment_pattern_net_lvalue
    )
  ),

  variable_lvalue: $ => choice(
    prec.left(PREC.PARENT, seq(
      optional(choice(
        seq($.implicit_class_handle, '.'),
        $.package_scope
      )),
      $._hierarchical_variable_identifier,
      optional($.select1)
    )),
    prec.left(PREC.CONCAT, seq('{', sep1(',', $.variable_lvalue), '}')),
    prec.left(PREC.ASSIGN, seq(
      optional($._assignment_pattern_expression_type),
      $.assignment_pattern_variable_lvalue
    )),
    $.streaming_concatenation
  ),

  nonrange_variable_lvalue: $ => prec.left(PREC.PARENT, seq(
    optional(choice(
      seq($.implicit_class_handle, '.'),
      $.package_scope
    )),
    $._hierarchical_variable_identifier,
    optional($.nonrange_select1)
  )),

  // A.8.6 Operators

  unary_operator: $ => choice(
    '+', '-', '!', '~', '&', '~&', '|', '~|', '^', '~^', '^~'
  ),

  inc_or_dec_operator: $ => choice('++', '--'),

  // unary_module_path_operator = '~&' /
  //   '~|' /
  //   '~^' /
  //   '^~' /
  //   $('!'![ != ]) /
  //   $('~'!'=') /
  //   $('&'!'=') /
  //   $('|'!'=') /
  //   $('^'!'=')
  //
  // binary_module_path_operator = $('=='!'=') /
  //   $('!='!'=') /
  //   '&&' /
  //   '||' /
  //   $('&'!'=') /
  //   $('|'!'=') /
  //   $('^'!'=') /
  //   '^~' /
  //   '~^'

  /* A.8.7 Numbers */

  _number: $ => choice($.integral_number, $.real_number),

  integral_number: $ => choice(
    $.decimal_number,
    $.octal_number,
    $.binary_number,
    $.hex_number
  ),

  decimal_number: $ => choice(
    $.unsigned_number,
    token(seq(
      optseq(/[1-9][0-9_]*/, /\s*/),
      /'[sS]?[dD]/,
      /\s*/,
      /[0-9][0-9_]*/
    )),
    token(seq(
      optseq(/[1-9][0-9_]*/, /\s*/),
      /'[sS]?[dD]/,
      /\s*/,
      /[xXzZ?][_]*/
    ))
  ),

  binary_number: $ => token(seq(
    optseq(/[1-9][0-9_]*/, /\s*/),
    /'[sS]?[bB]/,
    /\s*/,
    /[01xXzZ?][01xXzZ?_]*/
  )),

  octal_number: $ => token(seq(
    optseq(/[1-9][0-9_]*/, /\s*/),
    /'[sS]?[oO]/,
    /\s*/,
    /[0-7xXzZ?][0-7xXzZ?_]*/
  )),

  hex_number: $ => token(seq(
    optseq(/[1-9][0-9_]*/, /\s*/),
    /'[sS]?[hH]/,
    /\s*/,
    /[0-9a-fA-FxXzZ?][0-9a-fA-FxXzZ?_]*/
  )),

  // NOTE: Embedded spaces are illegal.
  non_zero_unsigned_number: $ => token(/[1-9][0-9_]*/),

  real_number: $ => choice(
    $.fixed_point_number,
    token(/[0-9][0-9_]*(\.[0-9][0-9_]*)?[eE][+-]?[0-9][0-9_]*/)
  ),

  fixed_point_number: $ => token(/[0-9][0-9_]*\.[0-9][0-9_]*/),

  unsigned_number: $ => token(/[0-9][0-9_]*/),

  // The apostrophe ( ' ) in unbased_unsized_literal shall not be followed by white_space.
  unbased_unsized_literal: $ => choice('\'0', '\'1', /'[xXzZ]/),

  /* A.9 General */

  /* A.9.1 Attributes */

  attribute_instance: $ => seq('(*', sep1(',', $.attr_spec), '*)'),

  attr_spec: $ => seq($._attr_name, optseq('=', $.constant_expression)),

  _attr_name: $ => $._identifier,

  /* A.9.2 Comments */

  // comment: $ => one_line_comment | block_comment
  // one_line_comment: $ => // comment_text \n
  // block_comment: $ => /* comment_text */
  // comment_text: $ => { Any_ASCII_character }

  // http://stackoverflow.com/questions/13014947/regex-to-match-a-c-style-multiline-comment/36328890#36328890
  // from: https://github.com/tree-sitter/tree-sitter-c/blob/master/grammar.js
  comment: $ => token(choice(
    seq('//', /.*/),
    seq(
      '/*',
      /[^*]*\*+([^/*][^*]*\*+)*/,
      '/'
    )
  )),

  /* A.9.3 Identifiers */

  _array_identifier: $ => $._identifier,
  _block_identifier: $ => $._identifier,
  _bin_identifier: $ => $._identifier,
  c_identifier: $ => /[a-zA-Z_][a-zA-Z0-9_]*/,
  cell_identifier: $ => alias($._identifier, $.cell_identifier),
  checker_identifier: $ => alias($._identifier, $.checker_identifier),
  class_identifier: $ => alias($._identifier, $.class_identifier),
  class_variable_identifier: $ => $._variable_identifier,
  clocking_identifier: $ => alias($._identifier, $.clocking_identifier),
  config_identifier: $ => alias($._identifier, $.config_identifier),
  const_identifier: $ => alias($._identifier, $.const_identifier),
  constraint_identifier: $ => alias($._identifier, $.constraint_identifier),

  covergroup_identifier: $ => alias($._identifier, $.covergroup_identifier),

  // covergroup_variable_identifier = _variable_identifier
  cover_point_identifier: $ => alias($._identifier, $.cover_point_identifier),
  cross_identifier: $ => alias($._identifier, $.cross_identifier),
  dynamic_array_variable_identifier: $ => alias($._variable_identifier, $.dynamic_array_variable_identifier),
  enum_identifier: $ => alias($._identifier, $.enum_identifier),
  escaped_identifier: $ => seq('\\', /[^\s]*/),
  formal_identifier: $ => alias($._identifier, $.formal_identifier),
  formal_port_identifier: $ => alias($._identifier, $.formal_port_identifier),
  function_identifier: $ => alias($._identifier, $.function_identifier),
  generate_block_identifier: $ => alias($._identifier, $.generate_block_identifier),
  genvar_identifier: $ => alias($._identifier, $.genvar_identifier),
  _hierarchical_array_identifier: $ => $.hierarchical_identifier,
  _hierarchical_block_identifier: $ => $.hierarchical_identifier,
  _hierarchical_event_identifier: $ => $.hierarchical_identifier,

  hierarchical_identifier: $ => prec.left(seq(
    optseq('$root', '.'),
    repseq($._identifier, optional($.constant_bit_select1), '.'),
    $._identifier
  )),

  _hierarchical_net_identifier: $ => $.hierarchical_identifier,
  _hierarchical_parameter_identifier: $ => $.hierarchical_identifier,
  _hierarchical_property_identifier: $ => $.hierarchical_identifier,
  _hierarchical_sequence_identifier: $ => $.hierarchical_identifier,
  _hierarchical_task_identifier: $ => $.hierarchical_identifier,
  _hierarchical_tf_identifier: $ => $.hierarchical_identifier,
  _hierarchical_variable_identifier: $ => $.hierarchical_identifier,

  _identifier: $ => choice(
    $.simple_identifier,
    $.escaped_identifier
  ),

  index_variable_identifier: $ => alias($._identifier, $.index_variable_identifier),
  interface_identifier: $ => alias($._identifier, $.interface_identifier),
  interface_instance_identifier: $ => alias($._identifier, $.interface_instance_identifier),
  inout_port_identifier: $ => alias($._identifier, $.inout_port_identifier),
  input_port_identifier: $ => alias($._identifier, $.input_port_identifier),
  instance_identifier: $ => alias($._identifier, $.instance_identifier),
  library_identifier: $ => alias($._identifier, $.library_identifier),
  member_identifier: $ => alias($._identifier, $.member_identifier),
  method_identifier: $ => alias($._identifier, $.method_identifier),
  modport_identifier: $ => alias($._identifier, $.modport_identifier),
  _module_identifier: $ => $._identifier,
  _net_identifier: $ => $._identifier,
  _net_type_identifier: $ => $._identifier,
  output_port_identifier: $ => alias($._identifier, $.output_port_identifier),
  package_identifier: $ => alias($._identifier, $.package_identifier),

  package_scope: $ => choice(
    seq($.package_identifier, '::'),
    seq('$unit', '::')
  ),

  parameter_identifier: $ => alias($._identifier, $.parameter_identifier),
  port_identifier: $ => alias($._identifier, $.port_identifier),
  production_identifier: $ => alias($._identifier, $.production_identifier),
  program_identifier: $ => alias($._identifier, $.program_identifier),
  property_identifier: $ => alias($._identifier, $.property_identifier),

  ps_class_identifier: $ => seq(
    optional($.package_scope), $.class_identifier
  ),

  ps_covergroup_identifier: $ => seq(
    optional($.package_scope), $.covergroup_identifier
  ),

  ps_checker_identifier: $ => seq(
    optional($.package_scope), $.checker_identifier
  ),

  ps_identifier: $ => seq(
    optional($.package_scope), $._identifier
  ),

  ps_or_hierarchical_array_identifier: $ => seq(
    optional(choice(
      seq($.implicit_class_handle, '.'),
      $.class_scope,
      $.package_scope
    )),
    $._hierarchical_array_identifier
  ),

  ps_or_hierarchical_net_identifier: $ => choice(
    prec.left(PREC.PARENT, seq(optional($.package_scope), $._net_identifier)),
    $._hierarchical_net_identifier
  ),

  ps_or_hierarchical_property_identifier: $ => choice(
    seq(optional($.package_scope), $.property_identifier),
    $._hierarchical_property_identifier
  ),

  ps_or_hierarchical_sequence_identifier: $ => choice(
    seq(optional($.package_scope), $._sequence_identifier),
    $._hierarchical_sequence_identifier
  ),

  ps_or_hierarchical_tf_identifier: $ => choice(
    seq(optional($.package_scope), $.tf_identifier),
    $._hierarchical_tf_identifier
  ),

  ps_parameter_identifier: $ => choice(
    seq(
      optional(choice(
        $.package_scope,
        $.class_scope
      )),
      $.parameter_identifier
    ),
    seq(
      repseq(
        $.generate_block_identifier,
        optseq('[', $.constant_expression, ']'),
        '.'
      ),
      $.parameter_identifier
    )
  ),

  ps_type_identifier: $ => seq(
    optional(choice(
      seq('local', '::'),
      $.package_scope,
      $.class_scope
    )),
    $._type_identifier
  ),

  _sequence_identifier: $ => $._identifier,

  _signal_identifier: $ => $._identifier,

  // A simple_identifier or c_identifier shall
  // start with an alpha or underscore ( _ ) character,
  // shall have at least one character, and shall not have any spaces.
  simple_identifier: $ => /[a-zA-Z_][a-zA-Z0-9_$]*/,

  specparam_identifier: $ => alias($._identifier, $.specparam_identifier),

  // The $ character in a system_tf_identifier shall
  // not be followed by white_space. A system_tf_identifier shall not be escaped.
  system_tf_identifier: $ => /\$[a-zA-Z0-9_$]+/,

  task_identifier: $ => alias($._identifier, $.task_identifier),
  tf_identifier: $ => alias($._identifier, $.tf_identifier),
  terminal_identifier: $ => alias($._identifier, $.terminal_identifier),
  topmodule_identifier: $ => alias($._identifier, $.topmodule_identifier),
  _type_identifier: $ => $._identifier,
  _udp_identifier: $ => $._identifier,
  _variable_identifier: $ => $._identifier

  /* A.9.4 White space */

  // white_space: $ => space | tab | newline | eof};

};

module.exports = grammar({
  name: 'verilog',
  word: $ => $.simple_identifier,
  rules: rules,
  extras: $ => [/\s/, $.comment],
  inline: $ => [
    $.hierarchical_identifier,
    $._hierarchical_net_identifier,
    $._hierarchical_variable_identifier,
    $._hierarchical_tf_identifier,
    $._hierarchical_sequence_identifier,
    $._hierarchical_property_identifier,
    $._hierarchical_block_identifier,
    $._hierarchical_task_identifier,

    $.ps_or_hierarchical_net_identifier,
    $.ps_or_hierarchical_tf_identifier,
    $.ps_or_hierarchical_sequence_identifier,
    $.ps_or_hierarchical_property_identifier,

    $.ps_class_identifier,
    $.ps_covergroup_identifier,
    $.ps_parameter_identifier,
    $.ps_type_identifier,
    $.ps_checker_identifier,

    $.parameter_identifier,
    $.class_identifier,
    $.covergroup_identifier,
    $.enum_identifier,
    $.formal_port_identifier,
    $.genvar_identifier,
    $.specparam_identifier,
    $.tf_identifier,
    $._type_identifier,
    $._net_type_identifier,
    $._variable_identifier,
    $._udp_identifier,
    $.package_identifier,
    $.dynamic_array_variable_identifier,
    $.class_variable_identifier,
    $.interface_instance_identifier,
    $.interface_identifier,
    $._module_identifier,
    $.let_identifier,
    $.sequence_identifier,
    $._net_identifier,
    $.program_identifier,
    $.checker_identifier,
    $.member_identifier,
    $.port_identifier,
    $._block_identifier,
    $.instance_identifier,
    $.property_identifier,
    // $.input_port_identifier,
    // $.output_port_identifier,
    // $.inout_port_identifier,
    // $.input_identifier,
    // $.output_identifier,
    $.cover_point_identifier,
    $.cross_identifier
  ],

  conflicts: $ => [
    [$.constant_primary, $.primary],
    [$.implicit_class_handle, $.primary],
    [$.param_expression, $.primary],
    [$.primary, $.queue_dimension],
    [$._checker_or_generate_item, $._module_common_item],
    [$._checker_generate_item, $._module_common_item],
    [$.dpi_function_import_property, $.dpi_task_import_property],
    [$.checker_or_generate_item_declaration, $.package_or_generate_item_declaration],
    [$._module_or_generate_item_declaration, $.checker_or_generate_item_declaration],
    [$.interface_or_generate_item, $.module_or_generate_item],
    [$.array_method_name, $.method_call_body],
    [$.constraint_set, $.empty_unpacked_array_concatenation],
    [$._non_port_interface_item, $.interface_declaration],
    [$.non_port_program_item, $.program_declaration],
    [$.list_of_port_declarations, $.list_of_ports],
    [$.expression_or_dist, $.mintypmax_expression],
    [$.class_constructor_declaration, $.implicit_class_handle],
    [$.action_block, $.statement_or_null],
    [$.ansi_port_declaration, $.port_reference],
    [$.ansi_port_declaration, $.port],
    [$.net_port_header1, $.variable_port_header],
    [$._variable_dimension, $.ansi_port_declaration],
    [$._non_port_module_item, $.module_declaration],
    [$._expression_or_cond_pattern, $.tagged_union_expression],
    [$._covergroup_expression, $.mintypmax_expression],
    [$._covergroup_expression, $.concatenation],
    [$.delay2, $.delay_control],
    [$.delay3, $.delay_control],
    [$.delay_control, $.param_expression],
    [$.delay2, $.delay_control, $.param_expression],
    [$.property_expr, $.property_spec],
    [$.property_expr, $.sequence_expr],
    [$.nonrange_select1, $.select1],
    [$.class_method, $.constraint_prototype_qualifier],
    [$.class_method, $.method_qualifier],
    [$.bind_target_instance, $.bind_target_scope],
    [$.class_type, $.package_scope],
    [$._var_data_type, $.data_type_or_implicit1],
    [$.list_of_port_identifiers, $.list_of_variable_identifiers],
    [$.list_of_port_identifiers, $.list_of_variable_port_identifiers],
    [$.class_type, $.data_type, $.tf_port_item1],
    [$.class_type, $.data_type, $.interface_port_header, $.net_port_type1],
    [$.class_type, $.data_type, $.net_port_type1],
    [$._variable_dimension, $.list_of_port_identifiers],
    [$._sequence_actual_arg, $.property_expr],
    [$._hierarchical_event_identifier, $._sequence_identifier, $.event_control],
    [$._hierarchical_event_identifier, $.event_control],
    [$.let_list_of_arguments, $.sequence_list_of_arguments],
    [$.input_identifier, $.output_identifier],
    [$.constant_primary, $.path_delay_expression],
    [$.scalar_timing_check_condition, $.unary_operator],
    [$.mintypmax_expression, $.scalar_timing_check_condition],
    [$.delayed_data, $.delayed_reference],
    [$.list_of_arguments_parent, $.system_tf_call],
    [$.class_item_qualifier, $.lifetime],
    [$._property_qualifier, $.method_qualifier],
    [$.class_property, $.data_type_or_implicit1],
    [$.list_of_arguments_parent, $.mintypmax_expression],
    [$.module_path_primary, $.tf_call],
    [$._package_item, $.package_declaration],
    [$.concurrent_assertion_item, $.deferred_immediate_assertion_item, $.generate_block_identifier],
    [$.clockvar, $.variable_lvalue],
    [$._seq_input_list, $.combinational_entry],
    [$.constant_primary, $.primary],
    [$.let_expression, $.primary],
    [$.constant_primary, $.let_expression, $.primary],
    [$.primary, $.tf_call],
    [$.let_expression, $.primary, $.tf_call],
    [$.constant_primary, $.let_expression, $.primary, $.tf_call],
    [$.let_expression, $.primary, $.select_expression, $.tf_call],
    [$.constant_primary, $.let_expression, $.primary, $.select_expression, $.tf_call],
    [$.constant_primary, $.primary],
    [$.primary, $.variable_lvalue],
    [$.constant_primary, $.net_lvalue],
    [$.net_lvalue, $.variable_lvalue],
    [$.constant_primary, $.port_reference],
    [$.let_expression, $.primary],
    [$.constant_primary, $.let_expression, $.primary],
    [$.let_expression, $.primary, $.variable_lvalue],
    [$.constant_primary, $.let_expression, $.primary, $.variable_lvalue],
    [$.primary, $.tf_call],
    [$.primary, $.tf_call, $.variable_lvalue],
    [$.net_lvalue, $.primary, $.tf_call, $.variable_lvalue],
    [$.primary, $.sequence_instance, $.tf_call],
    [$.net_lvalue, $.primary, $.sequence_instance, $.tf_call],
    [$.let_expression, $.primary, $.tf_call],
    [$.constant_primary, $.let_expression, $.primary, $.tf_call],
    [$.let_expression, $.primary, $.tf_call, $.variable_lvalue],
    [$.constant_primary, $.let_expression, $.primary, $.tf_call, $.variable_lvalue],
    [$.let_expression, $.port_reference, $.primary, $.tf_call],
    [$.constant_primary, $.let_expression, $.port_reference, $.primary, $.tf_call, $.variable_lvalue],
    [$.constant_primary, $.generate_block_identifier],
    [$.constant_primary, $.generate_block_identifier, $.primary, $.sequence_instance, $.tf_call],
    [$.constant_primary, $.generate_block_identifier, $.primary, $.sequence_instance, $.tf_call, $.variable_lvalue],
    [$.constant_primary, $.generate_block_identifier, $.port_reference, $.primary, $.sequence_instance, $.tf_call, $.variable_lvalue],
    [$._sequence_identifier, $.let_expression],
    [$._sequence_identifier, $.let_expression, $.primary],
    [$._sequence_identifier, $.constant_primary, $.let_expression, $.primary],
    [$._sequence_identifier, $.let_expression, $.primary, $.variable_lvalue],
    [$._sequence_identifier, $.let_expression, $.sequence_instance, $.tf_call],
    [$._sequence_identifier, $.let_expression, $.primary, $.sequence_instance, $.tf_call],
    [$._sequence_identifier, $.constant_primary, $.let_expression, $.primary, $.sequence_instance, $.tf_call],
    [$._sequence_identifier, $.generate_block_identifier, $.let_expression, $.primary, $.sequence_instance, $.tf_call],
    [$._sequence_identifier, $.generate_block_identifier, $.let_expression, $.primary, $.sequence_instance, $.tf_call, $.variable_lvalue],
    [$._sequence_identifier, $.generate_block_identifier, $.let_expression, $.net_lvalue, $.primary, $.sequence_instance, $.tf_call, $.variable_lvalue],
    [$._assignment_pattern_expression_type, $.variable_lvalue],
    [$._assignment_pattern_expression_type, $.let_expression, $.primary],
    [$._assignment_pattern_expression_type, $.let_expression, $.primary, $.tf_call],
    [$.list_of_arguments_parent, $.sequence_instance],
    [$.let_expression, $.list_of_arguments_parent],
    [$.let_expression, $.list_of_arguments_parent, $.sequence_instance],
    [$.module_path_primary, $.primary],
    [$.module_path_primary, $.tf_call],
    [$.constant_primary, $.module_path_primary, $.tf_call],
    [$.constant_primary, $.let_expression, $.module_path_primary, $.primary, $.tf_call],
    [$.constant_primary, $.let_expression, $.module_path_primary, $.primary, $.tf_call, $.variable_lvalue],
    [$.constant_primary, $.data_type],
    [$.constant_primary, $.data_type, $.generate_block_identifier],
    [$.constant_primary, $.data_type, $.generate_block_identifier, $.primary, $.sequence_instance, $.tf_call, $.variable_lvalue],
    [$.class_type, $.data_type],
    [$.class_type, $.constant_primary, $.data_type],
    [$.class_type, $.data_type, $.let_expression, $.primary],
    [$.class_type, $.constant_primary, $.data_type, $.let_expression, $.primary],
    [$.class_type, $.data_type, $.let_expression, $.primary, $.tf_call],
    [$.class_type, $.constant_primary, $.data_type, $.let_expression, $.primary, $.tf_call],
    [$.let_expression, $.primary],
    [$.primary, $.tf_call],
    [$.primary, $.sequence_instance, $.tf_call],
    [$.let_expression, $.primary, $.tf_call],
    [$.let_expression, $.primary, $.terminal_identifier, $.tf_call],
    [$._sequence_identifier, $.let_expression],
    [$._sequence_identifier, $.let_expression, $.primary],
    [$._sequence_identifier, $.let_expression, $.sequence_instance, $.tf_call],
    [$._sequence_identifier, $.let_expression, $.primary, $.sequence_instance, $.tf_call],
    [$._sequence_identifier, $.let_expression, $.sequence_instance, $.terminal_identifier, $.tf_call],
    [$.net_lvalue, $.variable_lvalue],
    [$._simple_type, $.constant_primary],
    [$.constant_primary, $.primary],
    [$.constant_primary, $.generate_block_identifier],
    [$.interface_instantiation, $.program_instantiation],
    [$.interface_instantiation, $.module_instantiation, $.program_instantiation],
    [$.data_type, $.net_type_declaration],
    [$.class_type, $.data_type],
    [$.class_type, $.data_type, $.net_declaration],
    [$.class_type, $.data_type, $.net_type_declaration],
    [$.checker_instantiation, $.class_type, $.data_type],
    [$.checker_instantiation, $.class_type, $.data_type, $.net_declaration],
    [$.checker_instantiation, $.class_type, $.data_type, $.interface_port_declaration, $.net_declaration],
    [$.checker_instantiation, $.class_type, $.data_type, $.interface_instantiation, $.net_declaration, $.program_instantiation],
    [$.checker_instantiation, $.class_type, $.data_type, $.interface_instantiation, $.interface_port_declaration, $.net_declaration, $.program_instantiation],
    [$.checker_instantiation, $.class_type, $.data_type, $.interface_instantiation, $.module_instantiation, $.net_declaration, $.program_instantiation, $.udp_instantiation],
    [$.checker_instantiation, $.class_type, $.data_type, $.interface_instantiation, $.interface_port_declaration, $.module_instantiation, $.net_declaration, $.program_instantiation, $.udp_instantiation],
    [$.nonrange_variable_lvalue, $.variable_lvalue],
    [$._method_call_root, $.class_qualifier],
    [$._variable_dimension, $.variable_decl_assignment],
    [$._variable_dimension, $.packed_dimension],
    [$._variable_dimension, $.packed_dimension, $.variable_decl_assignment],
    [$._simple_type, $.constant_primary],
    [$._assignment_pattern_expression_type, $._simple_type, $.class_qualifier, $.constant_primary],
    [$.constant_primary, $.data_type],
    [$._assignment_pattern_expression_type, $._simple_type, $.class_qualifier, $.constant_primary, $.data_type],
    [$.constant_select1, $.unpacked_dimension],
    [$.packed_dimension, $.unpacked_dimension],
    [$._constant_part_select_range, $.packed_dimension],
    [$._constant_part_select_range, $.packed_dimension, $.unpacked_dimension],
    [$._part_select_range, $.packed_dimension],
    [$._part_select_range, $.packed_dimension, $.unpacked_dimension],
    [$._constant_part_select_range, $._part_select_range],
    [$._constant_part_select_range, $._part_select_range, $.packed_dimension],
    [$.inout_port_identifier, $.input_port_identifier],
    [$.inout_port_identifier, $.output_port_identifier],
    [$.inout_port_identifier, $.input_port_identifier, $.output_port_identifier],
    [$.checker_instantiation, $.named_port_connection],
    [$.checker_instantiation, $.hierarchical_instance],
    [$._sequence_actual_arg, $.event_expression],
    [$.event_expression, $.expression_or_dist],
    [$.event_expression, $.expression_or_dist, $.named_port_connection],
    [$.event_expression, $.expression_or_dist, $.ordered_port_connection],
    [$.event_expression, $.expression_or_dist, $.let_actual_arg],
    [$.module_path_primary, $.primary],
    [$.module_path_primary, $.primary_literal],
  ],
});
