/* eslint-disable arrow-parens */
/* eslint-disable camelcase */
/* eslint-disable-next-line spaced-comment */
/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

const BRACE1 = [['{', '}']];
const BRACE2 = [['{{', '}}'], ['⦃', '⦄']];
// const BRACES = [...BRACE1, ...BRACE2];
const IDIOM = [['(|', '|)'], ['⦇', '⦈']];
const PAREN = [['(', ')']];

// numbers and literals
const integer = /\-?(0x[0-9a-fA-F]+|[0-9]+)/;

module.exports = grammar({
  name: 'agda',

  word: $ => $.id,

  extras: $ => [
    $.comment,
    $.pragma,
    /\s|\\n/,
  ],

  externals: $ => [
    $._newline,
    $._indent,
    $._dedent,
  ],

  rules: {
    source_file: $ => repeat(seq($._declaration, $._newline)),


    // //////////////////////////////////////////////////////////////////////
    // Constants
    // //////////////////////////////////////////////////////////////////////

    _FORALL: _ => choice('forall', '∀'),
    _ARROW: _ => choice('->', '→'),
    _LAMBDA: _ => choice('\\', 'λ'),
    _ELLIPSIS: _ => choice('...', '…'),

    // //////////////////////////////////////////////////////////////////////
    // Top-level Declarations
    // //////////////////////////////////////////////////////////////////////

    // Declarations
    // indented, 1 or more declarations
    _declaration_block: $ => block($, $._declaration),

    // Declarations0: use `optional($._declaration_block)` instead
    // _declaration_block0: $ => block($, optional($._declaration)),

    // Declaration
    _declaration: $ => choice(
      $.fields,
      $.function,
      $.data,
      $.data_signature,
      $.record,
      $.record_signature,
      $.infix,
      $.generalize,
      $.mutual,
      $.abstract,
      $.private,
      $.instance,
      $.macro,
      $.postulate,
      $.primitive,
      $.open,
      $.import,
      $.module_macro,
      $.module,
      $.pragma,
      $.syntax,
      $.pattern,
      $.unquote_decl,
    ),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Field
    // //////////////////////////////////////////////////////////////////////

    // Fields
    fields: $ => seq(
      'field',
      $._signature_block,
    ),

    // ArgTypeSignatures
    _signature_block: $ => block($, $.signature),

    // ArgTypeSigs
    signature: $ => choice(
      seq(
        optional('overlap'),
        $._modal_arg_ids,
        ':',
        $.expr,
      ),
      seq(
        'instance',
        $._signature_block,
      ),
    ),

    // ModalArgIds
    _modal_arg_ids: $ => seq(repeat($.attribute), $._arg_ids),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Functions
    // //////////////////////////////////////////////////////////////////////

    // We are splitting FunClause into 2 cases:
    //  *. function declaration (':')
    //  *. function definitions ('=')
    // Doing so we can mark the LHS of a function declaration as 'function_name'

    // FunClause
    function: $ => choice(
      seq(
        optional($.attributes),
        alias($.lhs_decl, $.lhs),
        alias(optional($.rhs_decl), $.rhs),
        optional($.where),
      ),
      seq(
        optional($.attributes),
        alias($.lhs_defn, $.lhs),
        alias(optional($.rhs_defn), $.rhs),
        optional($.where),
      ),
    ),

    // LHS
    lhs_decl: $ => seq(
      alias($._with_exprs, $.function_name),
      optional($.rewrite_equations),
      optional($.with_expressions),
    ),
    lhs_defn: $ => prec(1, seq(
      $._with_exprs,
      optional($.rewrite_equations),
      optional($.with_expressions),
    )),

    // RHS
    rhs_decl: $ => seq(':', $.expr),
    rhs_defn: $ => seq('=', $.expr),

    // WithExpressions
    with_expressions: $ => seq('with', $.expr),

    // RewriteEquations
    rewrite_equations: $ => seq('rewrite', $._with_exprs),

    // WhereClause
    where: $ => seq(
      optional(seq(
        'module',
        $.bid,
      )),
      'where',
      optional($._declaration_block),
    ),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Data
    // //////////////////////////////////////////////////////////////////////

    data_name: $ => alias($.id, 'data_name'),

    data: $ => seq(
      choice('data', 'codata'),
      $.data_name,
      optional($._typed_untyped_bindings),
      optional(seq(':', $.expr)),
      'where',
      optional($._declaration_block),
    ),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Data Signature
    // //////////////////////////////////////////////////////////////////////

    data_signature: $ => seq(
      'data',
      $.data_name,
      optional($._typed_untyped_bindings),
      ':',
      $.expr,
    ),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Record
    // //////////////////////////////////////////////////////////////////////

    // Record
    record: $ => seq(
      'record',
      alias($._atom_no_curly, $.record_name),
      optional($._typed_untyped_bindings),
      optional(seq(':', $.expr)),
      $.record_declarations_block,
    ),

    // RecordDeclarations
    record_declarations_block: $ => seq(
      'where',
      indent($,
        // RecordDirectives
        repeat(seq($._record_directive, $._newline)),
        repeat(seq($._declaration, $._newline)),
      ),
    ),

    // RecordDirective
    _record_directive: $ => choice(
      $.record_constructor,
      $.record_constructor_instance,
      $.record_induction,
      $.record_eta,
    ),
    // RecordConstructorName
    record_constructor: $ => seq('constructor', $.id),

    // Declaration of record constructor name.
    record_constructor_instance: $ => seq(
      'instance',
      block($, $.record_constructor),
    ),

    // RecordInduction
    record_induction: _ => choice(
      'inductive',
      'coinductive',
    ),

    // RecordEta
    record_eta: _ => choice(
      'eta-equality',
      'no-eta-equality',
    ),


    // //////////////////////////////////////////////////////////////////////
    // Declaration: Record Signature
    // //////////////////////////////////////////////////////////////////////

    record_signature: $ => seq(
      'record',
      alias($._atom_no_curly, $.record_name),
      optional($._typed_untyped_bindings),
      ':',
      $.expr,
    ),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Infix
    // //////////////////////////////////////////////////////////////////////

    infix: $ => seq(
      choice('infix', 'infixl', 'infixr'),
      $.integer,
      repeat1($.bid),
    ),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Generalize
    // //////////////////////////////////////////////////////////////////////

    generalize: $ => seq(
      'variable',
      optional($._signature_block),
    ),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Mutual
    // //////////////////////////////////////////////////////////////////////

    mutual: $ => seq(
      'mutual',
      optional($._declaration_block),
    ),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Abstract
    // //////////////////////////////////////////////////////////////////////

    abstract: $ => seq(
      'abstract',
      optional($._declaration_block),
    ),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Private
    // //////////////////////////////////////////////////////////////////////

    private: $ => seq(
      'private',
      optional($._declaration_block),
    ),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Instance
    // //////////////////////////////////////////////////////////////////////

    instance: $ => seq(
      'instance',
      optional($._declaration_block),
    ),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Macro
    // //////////////////////////////////////////////////////////////////////

    macro: $ => seq(
      'macro',
      optional($._declaration_block),
    ),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Postulate
    // //////////////////////////////////////////////////////////////////////

    postulate: $ => seq(
      'postulate',
      optional($._declaration_block),
    ),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Primitive
    // //////////////////////////////////////////////////////////////////////

    primitive: $ => seq(
      'primitive',
      optional($._type_signature_block),
    ),

    // TypeSignatures
    _type_signature_block: $ => block($, $.type_signature),

    // TypeSigs
    type_signature: $ => seq(
      $._field_names,
      ':',
      $.expr,
    ),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Open
    // //////////////////////////////////////////////////////////////////////


    open: $ => seq(
      'open',
      choice($.import, $.module_name),
      optional($._atoms),
      optional($._import_directives),
    ),
    import: $ => seq('import', $.module_name),


    // ModuleName
    module_name: $ => $._qid,

    // ImportDirectives and shit
    _import_directives: $ => repeat1($.import_directive),
    import_directive: $ => choice(
      'public',
      seq('using', '(', $._comma_import_names, ')'),
      seq('hiding', '(', $._comma_import_names, ')'),
      seq('renaming', '(', sepR(';', $.renaming), ')'),
      seq('using', '(', ')'),
      seq('hiding', '(', ')'),
      seq('renaming', '(', ')'),
    ),

    // CommaImportNames
    _comma_import_names: $ => sepR(';', $._import_name),

    // Renaming
    renaming: $ => seq(
      optional('module'),
      $.id,
      'to',
      $.id,
    ),

    // ImportName
    _import_name: $ => seq(
      optional('module'), $.id,
    ),


    // //////////////////////////////////////////////////////////////////////
    // Declaration: Module Macro
    // //////////////////////////////////////////////////////////////////////

    // ModuleMacro
    module_macro: $ => seq(
      choice(
        seq('module', alias($._qid, $.module_name)),
        seq('open', 'module', alias($._qid, $.module_name)),
      ),
      optional($._typed_untyped_bindings),
      '=',
      $.module_application,
      repeat($.import_directive),
    ),

    // ModuleApplication
    module_application: $ => seq(
      $.module_name,
      choice(
        prec(1, brace_double($._ELLIPSIS)),
        optional($._atoms),
      ),
    ),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Module
    // //////////////////////////////////////////////////////////////////////

    // Module
    module: $ => seq(
      'module',
      alias(choice($._qid, '_'), $.module_name),
      optional($._typed_untyped_bindings),
      'where',
      optional($._declaration_block),
    ),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Pragma
    // //////////////////////////////////////////////////////////////////////

    // Pragma / DeclarationPragma
    pragma: _ => token(seq(
      '{-#',
      repeat(choice(
        /[^#]/,
        /#[^-]/,
        /#\-[^}]/,
      )),
      '#-}',
    )),

    // CatchallPragma
    catchall_pragma: _ => seq('{-#', 'CATCHALL', '#-}'),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Syntax
    // //////////////////////////////////////////////////////////////////////

    syntax: $ => seq(
      'syntax',
      $.id,
      $.hole_names,
      '=',
      repeat1($.id),
    ),

    // HoleNames
    hole_names: $ => repeat1($.hole_name),
    hole_name: $ => choice(
      $._simple_top_hole,
      brace($._simple_hole),
      brace_double($._simple_hole),
      brace($.id, '=', $._simple_hole),
      brace_double($.id, '=', $._simple_hole),
    ),

    // SimpleTopHole
    _simple_top_hole: $ => choice(
      $.id,
      paren($._LAMBDA, $.bid, $._ARROW, $.id),
    ),

    // SimpleHole
    _simple_hole: $ => choice(
      $.id,
      seq($._LAMBDA, $.bid, $._ARROW, $.id),
    ),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Pattern Synonym
    // //////////////////////////////////////////////////////////////////////

    // PatternSyn
    pattern: $ => seq(
      'pattern',
      $.id,
      optional($._lambda_bindings), // PatternSynArgs
      '=',
      $.expr,
    ),

    // //////////////////////////////////////////////////////////////////////
    // Declaration: Unquoting declarations
    // //////////////////////////////////////////////////////////////////////

    // UnquoteDecl
    unquote_decl: $ => choice(
      seq('unquoteDecl', '=', $.expr),
      seq('unquoteDecl', $._ids, '=', $.expr),
      seq('unquoteDef', $._ids, '=', $.expr),
    ),

    // //////////////////////////////////////////////////////////////////////
    // Names
    // //////////////////////////////////////////////////////////////////////

    // identifier: http://wiki.portal.chalmers.se/agda/pmwiki.php?n=ReferenceManual.Names
    id: _ => /([^\s\\.\"\(\)\{\}@\'\\_]|\\[^\sa-zA-Z]|_[^\s;\.\"\(\)\{\}@])[^\s;\.\"\(\)\{\}@]*/,

    // qualified identifier: http://wiki.portal.chalmers.se/agda/pmwiki.php?n=ReferenceManual.Names
    _qid: $ => prec.left(
      choice(
        // eslint-disable-next-line max-len
        alias(/(([^\s;\.\"\(\)\{\}@\'\\_]|\\[^\sa-zA-Z]|_[^\s;\.\"\(\)\{\}@])[^\s;\.\"\(\)\{\}@]*\.)*([^\s;\.\"\(\)\{\}@\'\\_]|\\[^\sa-zA-Z]|_[^\s;\.\"\(\)\{\}@])[^\s;\.\"\(\)\{\}@]*/, $.qid),
        alias($.id, $.qid),
      ),
    ),

    // BId
    bid: $ => alias(choice('_', $.id), 'bid'),

    // SpaceIds
    _ids: $ => repeat1($.id),

    _field_name: $ => alias($.id, $.field_name),
    _field_names: $ => repeat1($._field_name),

    // MaybeDottedId
    _maybe_dotted_id: $ => maybeDotted($._field_name),
    _maybe_dotted_ids: $ => repeat1($._maybe_dotted_id),

    // ArgIds
    _arg_ids: $ => repeat1($._arg_id),
    _arg_id: $ => choice(
      $._maybe_dotted_id,

      brace($._maybe_dotted_ids),
      brace_double($._maybe_dotted_ids),

      seq('.', brace($._field_names)),
      seq('.', brace_double($._field_names)),

      seq('..', brace($._field_names)),
      seq('..', brace_double($._field_names)),
    ),

    // CommaBIds / CommaBIdAndAbsurds
    _binding_ids_and_absurds: $ => prec(-1, choice(
      $._application,
      seq($._qid, '=', $._qid),
      seq($._qid, '=', '_'),
      seq('-', '=', $._qid),
      seq('-', '=', '_'),
    )),

    // Attribute
    attribute: $ => seq('@', $._expr_or_attr),
    attributes: $ => repeat1($.attribute),

    // //////////////////////////////////////////////////////////////////////
    // Expressions (terms and types)
    // //////////////////////////////////////////////////////////////////////

    // Expr
    expr: $ => choice(
      seq($._typed_bindings, $._ARROW, $.expr),
      seq(optional($.attributes), $._atoms, $._ARROW, $.expr),
      seq($._with_exprs, '=', $.expr),
      prec(-1, $._with_exprs), // lowest precedence
    ),
    stmt: $ => choice(
      seq($._typed_bindings, $._ARROW, $.expr),
      seq(optional($.attributes), $._atoms, $._ARROW, $.expr),
      seq($._with_exprs, '=', $.expr),
      prec(-1, $._with_exprs_stmt), // lowest precedence
    ),

    // WithExprs/Expr1
    _with_exprs: $ => seq(
      repeat(seq($._atoms, '|')),
      $._application,
    ),
    _with_exprs_stmt: $ => seq(
      repeat(seq($._atoms, '|')),
      $._application_stmt,
    ),

    // ExprOrAttr
    _expr_or_attr: $ => choice(
      $.literal,
      $._qid,
      paren($.expr),
    ),

    // Application
    _application: $ => seq(
      optional($._atoms),
      $._expr2,
    ),
    _application_stmt: $ => seq(
      optional($._atoms),
      $._expr2_stmt,
    ),

    // Expr
    _expr2_without_let: $ => choice(
      $.lambda,
      alias($.lambda_extended_or_absurd, $.lambda),
      $.forall,
      $.do,
      prec(-1, $.atom),
      seq('quoteGoal', $.id, 'in', $.expr),
      seq('tactic', $._atoms),
      seq('tactic', $._atoms, '|', $._with_exprs),
    ),
    _expr2: $ => choice(
      $._expr2_without_let,
      $.let,
    ),
    _expr2_stmt: $ => choice(
      $._expr2_without_let,
      alias($.let_in_do, $.let),
    ),

    // Expr3
    atom: $ => choice(
      $._atom_curly,
      $._atom_no_curly,
    ),
    // Application3 / OpenArgs
    _atoms: $ => repeat1($.atom),

    _atom_curly: $ => brace(optional($.expr)),

    _atom_no_curly: $ => choice(
      '_',
      'Prop',
      $.SetN,
      'quote',
      'quoteTerm',
      'quoteContext',
      'unquote',
      $.PropN,
      brace_double($.expr),
      idiom($.expr),
      seq('(', ')'),
      seq('{{', '}}'),
      seq('⦃', '⦄'),
      seq($.id, '@', $.atom),
      seq('.', $.atom),
      $.record_assignments,
      alias($.field_assignments, $.record_assignments),
      $._ELLIPSIS,
      $._expr_or_attr,
    ),

    // ForallBindings
    forall: $ => seq($._FORALL, $._typed_untyped_bindings, $._ARROW, $.expr),

    // LetBody
    let: $ => prec.right(seq(
      'let',
      // declarations
      optional($._indent),
      repeat(seq($._declaration, $._newline)),
      $._declaration,
      // in case that there's a newline between declarations and $._let_body
      optional($._newline),

      $._let_body,
    )),

    // special `let...in` in do statements
    let_in_do: $ => prec.right(seq(
      'let',
      // declarations
      optional($._indent),
      repeat(seq($._declaration, $._newline)),
      $._declaration,
      //
      choice(
        seq($._newline, $._dedent),
        // covers the newline between declarations and $._let_body
        seq($._newline, $._let_body),
        // covers the rest of the cases
        $._let_body,
      ),
    )),

    _let_body: $ => seq(
      'in',
      $.expr,
    ),

    // LamBindings
    lambda: $ => seq(
      $._LAMBDA,
      $._lambda_bindings,
      $._ARROW,
      $.expr,
    ),

    // LamBinds
    _lambda_bindings: $ => seq(
      repeat($._typed_untyped_binding),
      choice(
        $._typed_untyped_binding,
        seq('(', ')'),
        seq('{', '}'),
        seq('{{', '}}'),
        seq('⦃', '⦄'),
      ),
    ),

    // ExtendedOrAbsurdLam
    lambda_extended_or_absurd: $ => seq(
      $._LAMBDA,
      choice(
        // LamClauses (single non absurd lambda clause)
        brace($.lambda_clause),
        // LamClauses
        brace($._lambda_clauses),
        // LamWhereClauses
        seq('where', $._lambda_clauses),
        // AbsurdLamBindings
        $._lambda_bindings,
      ),
    ),

    // bunch of `$._lambda_clause_maybe_absurd` sep by ';'
    _lambda_clauses: $ => prec.left(seq(
      repeat(seq($._lambda_clause_maybe_absurd, ';')),
      $._lambda_clause_maybe_absurd,
    )),

    // AbsurdLamBindings | AbsurdLamClause
    _lambda_clause_maybe_absurd: $ => prec.left(choice(
      $.lambda_clause_absurd,
      $.lambda_clause,
    )),

    // AbsurdLamClause
    lambda_clause_absurd: $ => seq(
      optional($.catchall_pragma),
      $._application,
    ),

    // NonAbsurdLamClause
    lambda_clause: $ => seq(
      optional($.catchall_pragma),
      optional($._atoms), // Application3PossiblyEmpty
      $._ARROW,
      $.expr,
    ),

    // DoStmts
    do: $ => seq('do',
      block($, $._do_stmt),
    ),

    // DoStmt
    _do_stmt: $ => seq(
      $.stmt,
      optional($.do_where),
    ),

    // DoWhere
    do_where: $ => seq(
      'where',
      $._lambda_clauses,
    ),

    // RecordAssignments
    record_assignments: $ => seq(
      'record',
      brace(optional($._record_assignments)),
    ),

    field_assignments: $ => seq(
      'record',
      $._atom_no_curly,
      brace(optional($._field_assignments)),
    ),

    // RecordAssignments1
    _record_assignments: $ => seq(
      repeat(seq($._record_assignment, ';')),
      $._record_assignment,
    ),


    // FieldAssignments1
    _field_assignments: $ => seq(
      repeat(seq($.field_assignment, ';')),
      $.field_assignment,
    ),

    // RecordAssignment
    _record_assignment: $ => choice(
      $.field_assignment,
      $.module_assignment,
    ),

    // FieldAssignment
    field_assignment: $ => seq(
      alias($.id, $.field_name),
      '=',
      $.expr,
    ),

    // ModuleAssignment
    module_assignment: $ => seq(
      $.module_name,
      optional($._atoms),
      optional($._import_directives),
    ),


    // //////////////////////////////////////////////////////////////////////
    // Bindings
    // //////////////////////////////////////////////////////////////////////

    // TypedBinding
    _typed_bindings: $ => repeat1($.typed_binding),
    typed_binding: $ => choice(
      maybeDotted(choice(
        paren($._application, ':', $.expr),
        brace($._binding_ids_and_absurds, ':', $.expr),
        brace_double($._binding_ids_and_absurds, ':', $.expr),
      )),
      paren($.attributes, $._application, ':', $.expr),
      brace($.attributes, $._binding_ids_and_absurds, ':', $.expr),
      brace_double($.attributes, $._binding_ids_and_absurds, ':', $.expr),
      paren($.open),
      paren('let', $._declaration_block),
    ),

    // TypedUntypedBindings1
    _typed_untyped_bindings: $ => repeat1($._typed_untyped_binding),
    _typed_untyped_binding: $ => choice(
      $.untyped_binding,
      $.typed_binding,
    ),

    // DomainFreeBinding / DomainFreeBindingAbsurd
    untyped_binding: $ => choice( // 13 variants
      maybeDotted(choice(
        $.bid,
        brace($._binding_ids_and_absurds),
        brace_double($._binding_ids_and_absurds),
      )),
      paren($._binding_ids_and_absurds),
      paren($.attributes, $._binding_ids_and_absurds),
      brace($.attributes, $._binding_ids_and_absurds),
      brace_double($.attributes, $._binding_ids_and_absurds),
    ),

    // //////////////////////////////////////////////////////////////////////
    // Literals
    // //////////////////////////////////////////////////////////////////////

    // -- Literals
    // <0,code> \'             { litChar }
    // <0,code,pragma_> \"     { litString }
    // <0,code> @integer       { literal LitNat }
    // <0,code> @float         { literal LitFloat }
    integer: _ => integer,
    string: _ => /\".*\"/,
    literal: _ => choice(
      integer,
      /\".*\"/,
    ),

    // //////////////////////////////////////////////////////////////////////
    // Comment
    // //////////////////////////////////////////////////////////////////////

    comment: _ => token(choice(
      prec(100, seq('--', /.*/)),
      seq('{--}'),
      seq(
        '{-',
        /[^#]/,
        repeat(choice(
          /[^-]/, // anything but -
          /-[^}]/, // - not followed by }
        )),
        /-}/,
      ),
    )),

    // setN
    SetN: $ => prec.right(2, seq('Set', optional($.atom))),


    // //////////////////////////////////////////////////////////////////////
    // Unimplemented
    // //////////////////////////////////////////////////////////////////////


    // propN
    PropN: _ => 'propN',

  },
});


// //////////////////////////////////////////////////////////////////////
// Generic combinators
// //////////////////////////////////////////////////////////////////////

/**
 * Creates a rule to match one or more of the rules separated by `sep`.
 *
 * @param {RuleOrLiteral} sep
 *
 * @param {RuleOrLiteral} rule
 *
 * @return {SeqRule}
 *
 */
function sepR(sep, rule) {
  return seq(rule, repeat(seq(sep, rule)));
}

/**
  * Creates a rule that requires indentation before and dedentation after.
  *
  * @param {GrammarSymbols<any>} $
  *
  * @param {RuleOrLiteral[]} rule
  *
  * @return {SeqRule}
  *
  */
function indent($, ...rule) {
  return seq(
    $._indent,
    ...rule,
    $._dedent,
  );
}

// 1 or more $RULE ending with a NEWLINE
/**
  * Creates a rule that uses an indentation block, where each line is a rule.
  * The indentation is required before and dedentation is required after.
  *
  * @param {GrammarSymbols<any>} $
  *
  * @param {RuleOrLiteral} rules
  *
  * @return {SeqRule}
  */
function block($, rules) {
  return indent($, repeat1(seq(rules, $._newline)));
}

// //////////////////////////////////////////////////////////////////////
// Language-specific combinators
// //////////////////////////////////////////////////////////////////////

/**
  * Creates a rule that matches a rule with a dot or two dots in front.
  *
  * @param {RuleOrLiteral} rule
  *
  * @return {ChoiceRule}
  */
function maybeDotted(rule) {
  return choice(
    rule, // Relevant
    seq('.', rule), // Irrelevant
    seq('..', rule), // NonStrict
  );
}

/**
  * Flattens an array of arrays.
  *
  * @param {Array<Array<Array<string>>>} arrOfArrs
  *
  * @return {Array<Array<string>>}
  *
  */
function flatten(arrOfArrs) {
  return arrOfArrs.reduce((res, arr) => [...res, ...arr], []);
}

/**
  * A callback function that takes a left and right string and returns a rule.
  * @callback encloseWithCallback
  * @param {string} left
  * @param {string} right
  * @return {RuleOrLiteral}
  * @see encloseWith
  * @see enclose
  */

/**
  * Creates a rule that matches a sequence of rules enclosed by a pair of strings.
  *
  * @param {encloseWithCallback} fn
  *
  * @param {Array<Array<Array<string>>>} pairs
  *
  * @return {ChoiceRule}
  *
  */
function encloseWith(fn, ...pairs) {
  return choice(...flatten(pairs).map(([left, right]) => fn(left, right)));
}

/**
  *
  * @param {RuleOrLiteral} expr
  *
  * @param {Array<Array<Array<string>>>} pairs
  *
  * @return {ChoiceRule}
  *
  */
function enclose(expr, ...pairs) {
  return encloseWith((left, right) => seq(left, expr, right), ...pairs);
}

/**
  * Creates a rule that matches a sequence of rules enclosed by `(` and `)`.
  *
  * @param {RuleOrLiteral[]} rules
  *
  * @return {ChoiceRule}
  *
  */
function paren(...rules) {
  return enclose(seq(...rules), PAREN);
}

/**
  * Creates a rule that matches a sequence of rules enclosed by `{` and `}`.
  *
  * @param {RuleOrLiteral[]} rules
  *
  * @return {ChoiceRule}
  *
  */
function brace(...rules) {
  return enclose(seq(...rules), BRACE1);
}

/**
  * Creates a rule that matches a sequence of rules enclosed by `{{` and `}}`.
  *
  * @param {RuleOrLiteral[]} rules
  *
  * @return {ChoiceRule}
  *
  */
function brace_double(...rules) {
  return enclose(seq(...rules), BRACE2);
}

/**
  * Creates a rule that matches a sequence of rules enclosed by `(|` and `|)`.
  *
  * @param {RuleOrLiteral[]} rules
  *
  * @return {ChoiceRule}
  *
  */
function idiom(...rules) {
  return enclose(seq(...rules), IDIOM);
}
