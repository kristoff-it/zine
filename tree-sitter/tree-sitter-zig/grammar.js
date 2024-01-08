const AMPERSAND = "&",
    AMPERSANDEQUAL = "&=",
    ASTERISK = "*",
    ASTERISK2 = "**",
    ASTERISKEQUAL = "*=",
    ASTERISKPERCENT = "*%",
    ASTERISKPERCENTEQUAL = "*%=",
    ASTERISKPIPE = "*|",
    ASTERISKPIPEEQUAL = "*|=",
    CARET = "^",
    CARETEQUAL = "^=",
    COLON = ":",
    COMMA = ",",
    DOT = ".",
    DOT2 = "..",
    DOT3 = "...",
    DOTASTERISK = ".*",
    DOTQUESTIONMARK = ".?",
    EQUAL = "=",
    EQUALEQUAL = "==",
    EQUALRARROW = "=>",
    EXCLAMATIONMARK = "!",
    EXCLAMATIONMARKEQUAL = "!=",
    LARROW = "<",
    LARROW2 = "<<",
    LARROW2PIPE = "<<|",
    LARROW2PIPEEQUAL = "<<|=",
    LARROW2EQUAL = "<<=",
    LARROWEQUAL = "<=",
    LBRACE = "{",
    LBRACKET = "[",
    LPAREN = "(",
    MINUS = "-",
    MINUSEQUAL = "-=",
    MINUSPERCENT = "-%",
    MINUSPERCENTEQUAL = "-%=",
    MINUSPIPE = "-|",
    MINUSPIPEEQUAL = "-|=",
    MINUSRARROW = "->",
    PERCENT = "%",
    PERCENTEQUAL = "%=",
    PIPE = "|",
    PIPE2 = "||",
    PIPEEQUAL = "|=",
    PLUS = "+",
    PLUS2 = "++",
    PLUSEQUAL = "+=",
    PLUSPERCENT = "+%",
    PLUSPERCENTEQUAL = "+%=",
    PLUSPIPE = "+|",
    PLUSPIPEEQUAL = "+|=",
    LETTERC = "c",
    QUESTIONMARK = "?",
    RARROW = ">",
    RARROW2 = ">>",
    RARROW2EQUAL = ">>=",
    RARROWEQUAL = ">=",
    RBRACE = "}",
    RBRACKET = "]",
    RPAREN = ")",
    SEMICOLON = ";",
    SLASH = "/",
    SLASHEQUAL = "/=",
    TILDE = "~",
    PREC = {
        curly: 1,
        assign: 2,
        primary: 3,
        or: 4,
        and: 5,
        comparative: 6,
        bitwise: 7,
        bitshift: 8,
        addition: 9,
        multiply: 10,
        prefix: 11,
    },
    buildin_type = [
        "bool",
        "f16",
        "f32",
        "f64",
        "f128",
        "void",
        "type",
        "anyerror",
        "anyframe",
        "anyopaque",
        "noreturn",
        "isize",
        "usize",
        "comptime_int",
        "comptime_float",
        "c_short",
        "c_ushort",
        "c_int",
        "c_uint",
        "c_long",
        "c_ulong",
        "c_longlong",
        "c_ulonglong",
        "c_longdouble",
        /(i|u)[0-9]+/,
    ],
    bin = /[01]/,
    bin_ = seq(optional("_"), bin),
    oct = /[0-7]/,
    oct_ = seq(optional("_"), oct),
    hex = /[0-9a-fA-F]/,
    hex_ = seq(optional("_"), hex),
    dec = /[0-9]/,
    dec_ = seq(optional("_"), dec),
    bin_int = seq(bin, repeat(bin_)),
    oct_int = seq(oct, repeat(oct_)),
    dec_int = seq(dec, repeat(dec_)),
    hex_int = seq(hex, repeat(hex_)),
    unescaped_string_fragment = token.immediate(prec(1, /[^"\\\{\}]+/)),
    unescaped_char_fragment = token.immediate(prec(1, /[^'\\]/));

module.exports = grammar({
    name: "zig",

    externals: (_) => [],
    inline: ($) => [$.Variable],
    extras: ($) => [/\s/, $.line_comment],
    conflicts: ($) => [[$.LoopExpr], [$.LoopTypeExpr]],
    rules: {
        source_file: ($) =>
            seq(optional($.container_doc_comment), optional($._ContainerMembers)),

        // *** Top level ***
        _ContainerMembers: ($) =>
            repeat1(
                choice($._ContainerDeclarations, seq($.ContainerField, optional(COMMA)))
            ),

        _ContainerDeclarations: ($) =>
            choice(
                $.TestDecl,
                $.ComptimeDecl,
                seq(
                    optional($.doc_comment),
                    optional(keyword("pub", $)),
                    $.Decl
                )
            ),

        TestDecl: ($) =>
            seq(
                optional($.doc_comment),
                keyword("test", $),
                optional(choice($.STRINGLITERALSINGLE, $.IDENTIFIER)),
                $.Block
            ),

        ComptimeDecl: ($) =>
            seq(keyword("comptime", $), $.Block),

        Decl: ($) =>
            choice(
                seq(
                    optional(choice(
                        keyword("export", $),
                        seq(keyword("extern", $), optional($.STRINGLITERALSINGLE)),
                        keyword(choice("inline", "noinline"), $)
                    )),
                    $.FnProto,
                    choice(SEMICOLON, $.Block)
                ),
                seq(
                    optional(
                        choice(
                            keyword("export", $),
                            seq(keyword("extern", $), optional($.STRINGLITERALSINGLE))
                        )
                    ),
                    optional(keyword("threadlocal", $)),
                    $.VarDecl
                ),
                seq(keyword("usingnamespace", $), $._Expr, SEMICOLON)
            ),

        FnProto: ($) =>
            seq(
                keyword("fn", $),
                optional(field("function", $.IDENTIFIER)),
                $.ParamDeclList,
                optional($.ByteAlign),
                optional($.AddrSpace),
                optional($.LinkSection),
                optional($.CallConv),
                optional(field("exception", EXCLAMATIONMARK)),
                $._TypeExpr
            ),

        VarDecl: ($) =>
            seq(
                keyword(choice("const", "var"), $),
                field("variable_type_function", $.IDENTIFIER),
                optional(seq(COLON, $._TypeExpr)),
                optional($.ByteAlign),
                optional($.AddrSpace),
                optional($.LinkSection),
                optional(seq(EQUAL, $._Expr)),
                SEMICOLON
            ),

        ContainerField: ($) =>
            prec(PREC.assign,
                seq(
                    optional($.doc_comment),
                    optional(keyword("comptime", $)),
                    choice(
                        seq(
                          field("field_member", choice(
                            $.IDENTIFIER,
                            alias($.BuildinTypeExpr, $.IDENTIFIER)
                          )),
                          COLON,
                          optional($.ArrayTypeStart),
                          $._TypeExpr,
                        ),
                        // NOTE: $._TypeExpr already include fn
                        $._TypeExpr
                    ),
                    optional($.ByteAlign),
                    optional(seq(EQUAL, $._Expr))
                )
            ),

        // *** Block Level ***

        Statement: ($) =>
            prec(
                PREC.curly,
                choice(
                    seq(optional(keyword("comptime", $)), $.VarDecl),
                    seq(
                        choice(
                            keyword(choice("comptime", "nosuspend", "defer", "suspend"), $),
                            seq(keyword("errdefer", $), optional($.Payload))
                        ),
                        $.BlockExprStatement
                    ),
                    $.IfStatement,
                    $.LabeledStatement,
                    $.SwitchExpr,
                    seq($.AssignExpr, SEMICOLON)
                )
            ),

        IfStatement: ($) =>
            choice(
                seq($.IfPrefix, $.BlockExpr, optional($._ElseStatementTail)),
                seq($.IfPrefix, $.AssignExpr, choice(SEMICOLON, $._ElseStatementTail))
            ),
        _ElseStatementTail: ($) =>
            seq(keyword("else", $), optional($.Payload), $.Statement),

        LabeledStatement: ($) =>
            prec(
                PREC.curly,
                seq(optional($.BlockLabel), choice($.Block, $.LoopStatement))
            ),

        LoopStatement: ($) =>
            seq(
                optional(keyword("inline", $)),
                choice($.ForStatement, $.WhileStatement)
            ),

        ForStatement: ($) =>
            choice(
                seq($.ForPrefix, $.BlockExpr, optional($._ElseStatementTail)),
                seq($.ForPrefix, $.AssignExpr, choice(SEMICOLON, $._ElseStatementTail))
            ),

        WhileStatement: ($) =>
            choice(
                seq($.WhilePrefix, $.BlockExpr, optional($._ElseStatementTail)),
                seq(
                    $.WhilePrefix,
                    $.AssignExpr,
                    choice(SEMICOLON, $._ElseStatementTail)
                )
            ),

        BlockExprStatement: ($) =>
            choice($.BlockExpr, seq($.AssignExpr, SEMICOLON)),

        BlockExpr: ($) => prec(PREC.curly, seq(optional($.BlockLabel), $.Block)),

        // *** Expression Level ***

        AssignExpr: ($) =>
            prec(PREC.assign, seq($._Expr, optional(seq($.AssignOp, $._Expr)))),

        _Expr: ($) => choice($.BinaryExpr, $.UnaryExpr, $._PrimaryExpr),

        BinaryExpr: ($) => {
            const table = [
                [PREC.or, "or"],
                [PREC.and, "and"],
                [PREC.comparative, $.CompareOp],
                [PREC.bitwise, $.BitwiseOp],
                [PREC.bitshift, $.BitShiftOp],
                [PREC.addition, $.AdditionOp],
                [PREC.multiply, $.MultiplyOp],
            ];

            return choice(
                ...table.map(([precedence, operator]) =>
                    prec.left(
                        precedence,
                        seq(
                            field("left", $._Expr),
                            field("operator", operator),
                            field("right", $._Expr)
                        )
                    )
                )
            );
        },

        UnaryExpr: ($) =>
            prec.left(
                PREC.prefix,
                seq(field("operator", $.PrefixOp), field("left", $._Expr))
            ),

        _PrimaryExpr: ($) =>
            // INFO: This should be right or ErrorUnionExpr give error
            prec.right(
                choice(
                    $.AsmExpr,
                    $.IfExpr,
                    seq(keyword("break", $), optional($.BreakLabel), optional($._Expr)),
                    seq(keyword("continue", $), optional($.BreakLabel)),
                    seq(keyword(choice("comptime", "nosuspend", "resume"), $), $._Expr),
                    seq(keyword("return", $), optional($._Expr)),
                    seq(optional($.BlockLabel), $.LoopExpr),
                    $.Block,
                    $._CurlySuffixExpr
                )
            ),

        IfExpr: ($) =>
            prec.right(seq($.IfPrefix, $._Expr, optional($._ElseExprTail))),

        _ElseExprTail: ($) => seq(keyword("else", $), optional($.Payload), $._Expr),

        Block: ($) => seq(LBRACE, repeat($.Statement), RBRACE),

        LoopExpr: ($) =>
            seq(optional(keyword("inline", $)), choice($.ForExpr, $.WhileExpr)),

        ForExpr: ($) =>
            prec.right(seq($.ForPrefix, $._Expr, optional($._ElseExprTail))),

        WhileExpr: ($) =>
            prec.right(seq($.WhilePrefix, $._Expr, optional($._ElseExprTail))),

        _CurlySuffixExpr: ($) =>
            // INFO: solve #1 issue
            prec(PREC.curly, seq($._TypeExpr, optional($.InitList))),

        InitList: ($) =>
            choice(
                seq(LBRACE, sepBy1(COMMA, $.FieldInit), RBRACE),
                seq(LBRACE, sepBy1(COMMA, $._Expr), RBRACE),
                seq(LBRACE, RBRACE)
            ),

        _TypeExpr: ($) => seq(repeat($.PrefixTypeOp), $.ErrorUnionExpr),

        ErrorUnionExpr: ($) =>
            // INFO: This be right or this will parse the code below to ErrorUnionExpr instead of Statement
            //  fn foo3(b: usize) Error!usize {
            //     return b;
            // }
            prec.right(
                seq(
                    $.SuffixExpr,
                    optional(seq(field("exception", EXCLAMATIONMARK), $._TypeExpr))
                )
            ),

        SuffixExpr: ($) =>
            // INFO: solve #1 issue
            prec.right(
                seq(
                    optional(keyword("async", $)),
                    choice(
                        $._PrimaryTypeExpr,
                        field("variable_type_function", $.IDENTIFIER),
                    ),
                    repeat(
                        choice(
                            $.SuffixOp,
                            $.FieldOrFnCall,
                            $.FnCallArguments,
                        )
                    )
                )
            ),

        FieldOrFnCall: ($) =>
            prec.right(
                choice(
                    seq(DOT, field("field_access", $.IDENTIFIER)),
                    seq(DOT, field("function_call", $.IDENTIFIER), $.FnCallArguments)
                )
            ),

        _PrimaryTypeExpr: ($) =>
            choice(
                seq($.BUILTINIDENTIFIER, $.FnCallArguments),
                $.CHAR_LITERAL,
                $.ContainerDecl,
                seq(DOT, field("field_constant", $.IDENTIFIER)),
                seq(DOT, $.InitList),
                $.ErrorSetDecl,
                $.FLOAT,
                $.FnProto,
                $.GroupedExpr,
                $.LabeledTypeExpr,
                $.IfTypeExpr,
                $.INTEGER,
                seq(keyword("comptime", $), $._TypeExpr),
                seq(keyword("error", $), DOT, field("field_constant", $.IDENTIFIER)),
                keyword("false", $),
                keyword("null", $),
                keyword("anyframe", $),
                keyword("true", $),
                keyword("undefined", $),
                keyword("unreachable", $),
                $._STRINGLITERAL,
                $.SwitchExpr,
                $.BuildinTypeExpr
            ),

        BuildinTypeExpr: (_) => token(choice(...buildin_type)),
        ContainerDecl: ($) =>
            seq(
                optional(keyword(choice("extern", "packed"), $)),
                $._ContainerDeclAuto
            ),

        ErrorSetDecl: ($) =>
            seq(
                keyword("error", $),
                LBRACE,
                sepBy(
                    COMMA,
                    seq(optional($.doc_comment), field("field_constant", $.IDENTIFIER))
                ),
                RBRACE
            ),

        GroupedExpr: ($) => seq(LPAREN, $._Expr, RPAREN),

        IfTypeExpr: ($) =>
            prec.right(seq($.IfPrefix, $._TypeExpr, optional($._ElseTypeExprTail))),

        _ElseTypeExprTail: ($) =>
            seq(keyword("else", $), optional($.Payload), $._TypeExpr),

        LabeledTypeExpr: ($) =>
            choice(
                seq($.BlockLabel, $.Block),
                seq(optional($.BlockLabel), $.LoopTypeExpr)
            ),

        LoopTypeExpr: ($) =>
            seq(
                optional(keyword("inline", $)),
                choice($.ForTypeExpr, $.WhileTypeExpr)
            ),

        ForTypeExpr: ($) =>
            prec.right(seq($.ForPrefix, $._TypeExpr, optional($._ElseTypeExprTail))),

        WhileTypeExpr: ($) =>
            prec.right(seq($.WhilePrefix, $._TypeExpr, optional($._ElseTypeExprTail))),

        SwitchExpr: ($) =>
            seq(
                keyword("switch", $),
                LPAREN,
                $._Expr,
                RPAREN,
                LBRACE,
                sepBy(COMMA, $.SwitchProng),
                RBRACE
            ),

        // *** Assembly ***

        AsmExpr: ($) =>
            seq(
                keyword("asm", $),
                optional(keyword("volatile", $)),
                LPAREN,
                $._Expr,
                optional($.AsmOutput),
                RPAREN
            ),

        AsmOutput: ($) =>
            seq(COLON, sepBy(COMMA, $.AsmOutputItem), optional($.AsmInput)),

        AsmOutputItem: ($) =>
            seq(
                LBRACKET,
                $.Variable,
                RBRACKET,
                $._STRINGLITERAL,
                LPAREN,
                choice(seq("->", $._TypeExpr), $.Variable),
                RPAREN
            ),

        AsmInput: ($) =>
            seq(COLON, sepBy(COMMA, $.AsmInputItem), optional($.AsmClobbers)),

        AsmInputItem: ($) =>
            seq(
                LBRACKET,
                $.Variable,
                RBRACKET,
                $._STRINGLITERAL,
                LPAREN,
                $._Expr,
                RPAREN
            ),

        AsmClobbers: ($) => seq(COLON, sepBy(COMMA, $._STRINGLITERAL)),

        // *** Helper grammar ***
        BreakLabel: ($) => seq(COLON, $.IDENTIFIER),

        BlockLabel: ($) => prec.left(seq(...blockLabel($))),

        FieldInit: ($) =>
            seq(DOT, field("field_member", $.IDENTIFIER), EQUAL, $._Expr),

        WhileContinueExpr: ($) => seq(COLON, LPAREN, $.AssignExpr, RPAREN),

        LinkSection: ($) => seq(keyword("linksection", $), LPAREN, $._Expr, RPAREN),

        AddrSpace: ($) => seq(keyword("addrspace", $), LPAREN, $._Expr, RPAREN),

        // Fn specific
        CallConv: ($) => seq(keyword("callconv", $), LPAREN, $._Expr, RPAREN),

        ParamDecl: ($) =>
            choice(
                seq(
                    optional($.doc_comment),
                    optional(keyword(choice("noalias", "comptime"), $)),
                    optional(seq(
                      field("parameter", choice(
                        $.IDENTIFIER,
                        alias($.BuildinTypeExpr, $.IDENTIFIER)
                      )),
                      COLON
                    )),
                    $.ParamType
                ),
                DOT3
            ),

        ParamType: ($) =>
            prec(PREC.curly, choice(keyword("anytype", $), $._TypeExpr)),

        // Control flow prefixes
        IfPrefix: ($) =>
            seq(keyword("if", $), LPAREN, $._Expr, RPAREN, optional($.PtrPayload)),

        WhilePrefix: ($) =>
            seq(
                keyword("while", $),
                LPAREN,
                $._Expr,
                RPAREN,
                optional($.PtrPayload),
                optional($.WhileContinueExpr)
            ),
        ForPrefix: ($) => seq(keyword("for", $), LPAREN, $.ForArgumentsList, RPAREN, $.PtrListPayload),

        // Payloads
        Payload: ($) => seq(PIPE, $.Variable, PIPE),

        PtrPayload: ($) => seq(PIPE, optional(ASTERISK), $.Variable, PIPE),

        PtrIndexPayload: ($) =>
            seq(
                PIPE,
                optional(ASTERISK),
                $.Variable,
                optional(seq(COMMA, $.Variable)),
                PIPE
            ),

        PtrListPayload: ($) => seq( PIPE, sepBy1(COMMA, seq(optional(ASTERISK), $.Variable)), PIPE),

        // Switch specific
        SwitchProng: ($) =>
            seq(optional("inline"), $.SwitchCase, EQUALRARROW, optional($.PtrIndexPayload), $.AssignExpr),

        SwitchCase: ($) => choice(sepBy1(COMMA, $.SwitchItem), keyword("else", $)),

        SwitchItem: ($) => seq($._Expr, optional(seq(DOT3, $._Expr))),

        // For specific
        ForArgumentsList: ($) => sepBy1(COMMA, $.ForItem),

        ForItem: ($) => seq($._Expr, optional(seq(DOT2,  optional($._Expr)))),

        AssignOp: (_) =>
            choice(
                ASTERISKEQUAL,
                ASTERISKPIPEEQUAL,
                SLASHEQUAL,
                PERCENTEQUAL,
                PLUSEQUAL,
                PLUSPIPEEQUAL,
                MINUSEQUAL,
                MINUSPIPEEQUAL,
                LARROW2EQUAL,
                LARROW2PIPEEQUAL,
                RARROW2EQUAL,
                AMPERSANDEQUAL,
                CARETEQUAL,
                PIPEEQUAL,
                ASTERISKPERCENTEQUAL,
                PLUSPERCENTEQUAL,
                MINUSPERCENTEQUAL,
                EQUAL
            ),
        CompareOp: (_) =>
            choice(
                EQUALEQUAL,
                EXCLAMATIONMARKEQUAL,
                LARROW,
                RARROW,
                LARROWEQUAL,
                RARROWEQUAL
            ),
        BitwiseOp: ($) =>
            choice(
                AMPERSAND,
                CARET,
                PIPE,
                keyword("orelse", $),
                seq(keyword("catch", $), optional($.Payload))
            ),

        BitShiftOp: (_) => choice(LARROW2, RARROW2, LARROW2PIPE),

        AdditionOp: (_) =>
            choice(
                PLUS,
                MINUS,
                PLUS2,
                PLUSPERCENT,
                MINUSPERCENT,
                PLUSPIPE,
                MINUSPIPE
            ),

        MultiplyOp: (_) =>
            choice(
                PIPE2,
                ASTERISK,
                SLASH,
                PERCENT,
                ASTERISK2,
                ASTERISKPERCENT,
                ASTERISKPIPE
            ),

        PrefixOp: ($) =>
            choice(
                EXCLAMATIONMARK,
                MINUS,
                TILDE,
                MINUSPERCENT,
                AMPERSAND,
                keyword("try", $),
                keyword("await", $)
            ),

        PrefixTypeOp: ($) =>
            choice(
                QUESTIONMARK,
                seq(keyword("anyframe", $), MINUSRARROW),
                seq(
                    $.SliceTypeStart,
                    repeat(
                        choice(
                            $.ByteAlign,
                            $.AddrSpace,
                            keyword(choice("const", "volatile", "allowzero"), $)
                        )
                    )
                ),

                seq(
                    $.PtrTypeStart,
                    repeat(
                        choice(
                            $.AddrSpace,
                            seq(
                                keyword("align", $),
                                LPAREN,
                                $._Expr,
                                optional(seq(COLON, $._Expr, COLON, $._Expr)),
                                RPAREN
                            ),
                            keyword(choice("const", "volatile", "allowzero"), $)
                        )
                    )
                ),
                $.ArrayTypeStart
            ),

        /*
          Given a sentinel-terminated expression, e.g. `foo[bar..bar: 0]`, note
          how "bar: " resembles the opening of a labeled block; due to that
          label-like syntax, Tree-sitter would try to parse what comes after the
          COLON as a block, which would obviously fail in this case. To work
          around that problem, we'll create a SentinelTerminatedExpr rule which
          starts like the the BlockLabel rule (hence why they share a common
          definition), but ends with an arbitrary Expr instead of a block.
          BlockLabel should have preferential precedence based on its usage sites
          throughout the rest of the grammar, thus this rule effectively serves
          as a fallback for the former.
        */
        _SentinelTerminatedExpr: ($) => choice(
          seq(...blockLabel($), $._Expr),
          seq(COLON, $._Expr),
          seq($._Expr, optional(seq(COLON, $._Expr)))
        ),

        SuffixOp: ($) =>
            choice(
                seq(
                    LBRACKET,
                    $._Expr,
                    optional(seq(DOT2, optional($._SentinelTerminatedExpr))),
                    RBRACKET
                ),
                DOTASTERISK,
                DOTQUESTIONMARK
            ),

        FnCallArguments: ($) => seq(LPAREN, sepBy(COMMA, $._Expr), RPAREN),

        // Ptr specific
        SliceTypeStart: ($) =>
            seq(LBRACKET, optional(seq(COLON, $._Expr)), RBRACKET),

        PtrTypeStart: ($) =>
            choice(
                ASTERISK,
                ASTERISK2,
                seq(
                    LBRACKET,
                    ASTERISK,
                    optional(choice(LETTERC, seq(COLON, $._Expr))),
                    RBRACKET
                )
            ),

        ArrayTypeStart: ($) => seq(
          LBRACKET,
          choice($._Expr, $.IDENTIFIER),
          optional(DOT2),
          optional(seq(COLON, choice($._Expr, $.IDENTIFIER))),
          RBRACKET
        ),

        // ContainerDecl specific
        _ContainerDeclAuto: ($) =>
            seq(
                $.ContainerDeclType,
                LBRACE,
                optional($.container_doc_comment),
                optional($._ContainerMembers),
                RBRACE
            ),

        ContainerDeclType: ($) =>
            choice(
                seq(
                  keyword("struct", $),
                  optional(seq(LPAREN, $._Expr, RPAREN))
                ),
                keyword("opaque", $),
                seq(keyword("enum", $), optional(seq(LPAREN, $._Expr, RPAREN))),
                seq(
                    keyword("union", $),
                    optional(
                        seq(
                            LPAREN,
                            choice(
                                seq(keyword("enum", $), optional(seq(LPAREN, $._Expr, RPAREN))),
                                $._Expr
                            ),
                            RPAREN
                        )
                    )
                )
            ),

        // Alignment
        ByteAlign: ($) => seq(keyword("align", $), LPAREN, $._Expr, RPAREN),

        // Lists
        ParamDeclList: ($) => seq(LPAREN, sepBy(COMMA, $.ParamDecl), RPAREN),

        // *** Tokens ***
        container_doc_comment: (_) =>
            token(repeat1(seq("//!", /[^\n]*/, /[ \n]*/))),
        doc_comment: (_) => token(repeat1(seq("///", /[^\n]*/, /[ \n]*/))),
        line_comment: (_) => token(seq("//", /.*/)),

        CHAR_LITERAL: ($) =>
            seq("'", choice(unescaped_char_fragment, $.EscapeSequence), "'"),

        FLOAT: (_) =>
            choice(
                token(
                    seq("0x", hex_int, ".", hex_int, optional(seq(/[pP][-+]?/, dec_int)))
                ),
                token(seq(dec_int, ".", dec_int, optional(seq(/[eE][-+]?/, dec_int)))),
                token(seq("0x", hex_int, /[pP][-+]?/, dec_int)),
                token(seq(dec_int, /[eE][-+]?/, dec_int))
            ),

        INTEGER: (_) =>
            choice(
                token(seq("0b", bin_int)),
                token(seq("0o", oct_int)),
                token(seq("0x", hex_int)),
                token(dec_int)
            ),

        EscapeSequence: (_) =>
            choice(
                seq(
                    "\\",
                    choice(/x[0-9a-fA-f]{2}/, /u\{[0-9a-fA-F]+\}/, /[nr\\t'"]/)
                ),
                "{{",
                "}}"
            ),

        FormatSequence: (_) =>
            seq(
                "{",
                /[0-9]*/,
                optional(choice(/[xXsedbocu*!?]{1}/, "any")),
                optional(
                    seq(
                        ":",
                        optional(/[^"\\\{\}]{1}[<^>]{1}[0-9]+/),
                        /.{0,1}[0-9]*/,
                    ))
                ,
                "}"
            ),

        STRINGLITERALSINGLE: ($) =>
            seq(
                '"',
                repeat(
                    choice(
                        unescaped_string_fragment,
                        $.EscapeSequence,
                        $.FormatSequence,
                        token.immediate('{'),
                        token.immediate('}')
                    )
                ),
                '"'
            ),

        LINESTRING: (_) => seq("\\\\", /[^\n]*/),

        _STRINGLITERAL: ($) => prec.left(choice($.STRINGLITERALSINGLE, repeat1($.LINESTRING))),

        Variable: ($) => field("variable", $.IDENTIFIER),

        IDENTIFIER: ($) =>
            choice(/[A-Za-z_][A-Za-z0-9_]*/, seq("@", $.STRINGLITERALSINGLE)),

        BUILTINIDENTIFIER: (_) => seq("@", /[A-Za-z_][A-Za-z0-9_]*/),
    },
});

function sepBy1(sep, rule) {
    return seq(rule, repeat(seq(sep, rule)), optional(sep));
}
function keyword(rule, _) {
    return rule;
    // return alias(rule, $.keyword);
}
function sepBy(sep, rule) {
    return optional(sepBy1(sep, rule));
}

/*
  This rule was extracted as a function for the sake of making
  _SentinelTerminatedExpr and BlockLabel share the same definition. Please check
  the comment of _SentinelTerminatedExpr for more context.
*/
function blockLabel($) {
  return [$.IDENTIFIER, COLON]
}
