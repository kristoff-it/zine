#include <tree_sitter/parser.h>

#if defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wmissing-field-initializers"
#endif

#define LANGUAGE_VERSION 14
#define STATE_COUNT 51
#define LARGE_STATE_COUNT 2
#define SYMBOL_COUNT 29
#define ALIAS_COUNT 0
#define TOKEN_COUNT 18
#define EXTERNAL_TOKEN_COUNT 0
#define FIELD_COUNT 0
#define MAX_ALIAS_SEQUENCE_LENGTH 6
#define PRODUCTION_ID_COUNT 1

enum {
  anon_sym_LBRACE = 1,
  anon_sym_RBRACE = 2,
  sym_tag_name_with_argument = 3,
  sym_tag_name_with_type = 4,
  sym_tag_name = 5,
  anon_sym_COLON = 6,
  anon_sym_SLASH = 7,
  anon_sym_DOT = 8,
  anon_sym_POUND = 9,
  anon_sym_TILDE = 10,
  anon_sym_LBRACK = 11,
  anon_sym_RBRACK = 12,
  sym_identifier = 13,
  sym_type = 14,
  sym__text = 15,
  sym__begin = 16,
  sym__end = 17,
  sym_document = 18,
  sym_description = 19,
  sym_tag = 20,
  sym_inline_tag = 21,
  sym__expression = 22,
  sym_qualified_expression = 23,
  sym_path_expression = 24,
  sym_member_expression = 25,
  sym_optional_identifier = 26,
  aux_sym_document_repeat1 = 27,
  aux_sym_description_repeat1 = 28,
};

static const char * const ts_symbol_names[] = {
  [ts_builtin_sym_end] = "end",
  [anon_sym_LBRACE] = "{",
  [anon_sym_RBRACE] = "}",
  [sym_tag_name_with_argument] = "tag_name",
  [sym_tag_name_with_type] = "tag_name",
  [sym_tag_name] = "tag_name",
  [anon_sym_COLON] = ":",
  [anon_sym_SLASH] = "/",
  [anon_sym_DOT] = ".",
  [anon_sym_POUND] = "#",
  [anon_sym_TILDE] = "~",
  [anon_sym_LBRACK] = "[",
  [anon_sym_RBRACK] = "]",
  [sym_identifier] = "identifier",
  [sym_type] = "type",
  [sym__text] = "_text",
  [sym__begin] = "_begin",
  [sym__end] = "_end",
  [sym_document] = "document",
  [sym_description] = "description",
  [sym_tag] = "tag",
  [sym_inline_tag] = "inline_tag",
  [sym__expression] = "_expression",
  [sym_qualified_expression] = "qualified_expression",
  [sym_path_expression] = "path_expression",
  [sym_member_expression] = "member_expression",
  [sym_optional_identifier] = "optional_identifier",
  [aux_sym_document_repeat1] = "document_repeat1",
  [aux_sym_description_repeat1] = "description_repeat1",
};

static const TSSymbol ts_symbol_map[] = {
  [ts_builtin_sym_end] = ts_builtin_sym_end,
  [anon_sym_LBRACE] = anon_sym_LBRACE,
  [anon_sym_RBRACE] = anon_sym_RBRACE,
  [sym_tag_name_with_argument] = sym_tag_name,
  [sym_tag_name_with_type] = sym_tag_name,
  [sym_tag_name] = sym_tag_name,
  [anon_sym_COLON] = anon_sym_COLON,
  [anon_sym_SLASH] = anon_sym_SLASH,
  [anon_sym_DOT] = anon_sym_DOT,
  [anon_sym_POUND] = anon_sym_POUND,
  [anon_sym_TILDE] = anon_sym_TILDE,
  [anon_sym_LBRACK] = anon_sym_LBRACK,
  [anon_sym_RBRACK] = anon_sym_RBRACK,
  [sym_identifier] = sym_identifier,
  [sym_type] = sym_type,
  [sym__text] = sym__text,
  [sym__begin] = sym__begin,
  [sym__end] = sym__end,
  [sym_document] = sym_document,
  [sym_description] = sym_description,
  [sym_tag] = sym_tag,
  [sym_inline_tag] = sym_inline_tag,
  [sym__expression] = sym__expression,
  [sym_qualified_expression] = sym_qualified_expression,
  [sym_path_expression] = sym_path_expression,
  [sym_member_expression] = sym_member_expression,
  [sym_optional_identifier] = sym_optional_identifier,
  [aux_sym_document_repeat1] = aux_sym_document_repeat1,
  [aux_sym_description_repeat1] = aux_sym_description_repeat1,
};

static const TSSymbolMetadata ts_symbol_metadata[] = {
  [ts_builtin_sym_end] = {
    .visible = false,
    .named = true,
  },
  [anon_sym_LBRACE] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_RBRACE] = {
    .visible = true,
    .named = false,
  },
  [sym_tag_name_with_argument] = {
    .visible = true,
    .named = true,
  },
  [sym_tag_name_with_type] = {
    .visible = true,
    .named = true,
  },
  [sym_tag_name] = {
    .visible = true,
    .named = true,
  },
  [anon_sym_COLON] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_SLASH] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_DOT] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_POUND] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_TILDE] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_LBRACK] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_RBRACK] = {
    .visible = true,
    .named = false,
  },
  [sym_identifier] = {
    .visible = true,
    .named = true,
  },
  [sym_type] = {
    .visible = true,
    .named = true,
  },
  [sym__text] = {
    .visible = false,
    .named = true,
  },
  [sym__begin] = {
    .visible = false,
    .named = true,
  },
  [sym__end] = {
    .visible = false,
    .named = true,
  },
  [sym_document] = {
    .visible = true,
    .named = true,
  },
  [sym_description] = {
    .visible = true,
    .named = true,
  },
  [sym_tag] = {
    .visible = true,
    .named = true,
  },
  [sym_inline_tag] = {
    .visible = true,
    .named = true,
  },
  [sym__expression] = {
    .visible = false,
    .named = true,
  },
  [sym_qualified_expression] = {
    .visible = true,
    .named = true,
  },
  [sym_path_expression] = {
    .visible = true,
    .named = true,
  },
  [sym_member_expression] = {
    .visible = true,
    .named = true,
  },
  [sym_optional_identifier] = {
    .visible = true,
    .named = true,
  },
  [aux_sym_document_repeat1] = {
    .visible = false,
    .named = false,
  },
  [aux_sym_description_repeat1] = {
    .visible = false,
    .named = false,
  },
};

static const TSSymbol ts_alias_sequences[PRODUCTION_ID_COUNT][MAX_ALIAS_SEQUENCE_LENGTH] = {
  [0] = {0},
};

static const uint16_t ts_non_terminal_alias_map[] = {
  0,
};

static const TSStateId ts_primary_state_ids[STATE_COUNT] = {
  [0] = 0,
  [1] = 1,
  [2] = 2,
  [3] = 3,
  [4] = 4,
  [5] = 5,
  [6] = 6,
  [7] = 7,
  [8] = 8,
  [9] = 9,
  [10] = 10,
  [11] = 11,
  [12] = 12,
  [13] = 13,
  [14] = 14,
  [15] = 15,
  [16] = 16,
  [17] = 17,
  [18] = 18,
  [19] = 19,
  [20] = 20,
  [21] = 21,
  [22] = 22,
  [23] = 23,
  [24] = 24,
  [25] = 11,
  [26] = 8,
  [27] = 15,
  [28] = 28,
  [29] = 29,
  [30] = 30,
  [31] = 31,
  [32] = 21,
  [33] = 33,
  [34] = 34,
  [35] = 33,
  [36] = 36,
  [37] = 37,
  [38] = 38,
  [39] = 39,
  [40] = 40,
  [41] = 41,
  [42] = 42,
  [43] = 43,
  [44] = 44,
  [45] = 45,
  [46] = 46,
  [47] = 47,
  [48] = 39,
  [49] = 49,
  [50] = 45,
};

static bool ts_lex(TSLexer *lexer, TSStateId state) {
  START_LEXER();
  switch (state) {
    case 0:
      if (eof) ADVANCE(21);
      if (lookahead == '\n') SKIP(19)
      if (lookahead == '#') ADVANCE(116);
      if (lookahead == '.') ADVANCE(115);
      if (lookahead == '/') ADVANCE(114);
      if (lookahead == ':') ADVANCE(112);
      if (lookahead == '@') ADVANCE(17);
      if (lookahead == '[') ADVANCE(118);
      if (lookahead == ']') ADVANCE(119);
      if (lookahead == '{') ADVANCE(22);
      if (lookahead == '}') ADVANCE(23);
      if (lookahead == '~') ADVANCE(117);
      if (('\t' <= lookahead && lookahead <= '\r') ||
          lookahead == ' ') SKIP(20)
      if (lookahead == '$' ||
          ('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(120);
      if (lookahead != 0 &&
          lookahead != '*') ADVANCE(126);
      END_STATE();
    case 1:
      if (lookahead == '\n') SKIP(1)
      if (lookahead == '*') SKIP(1)
      if (lookahead == '/') ADVANCE(127);
      if (lookahead == '@') ADVANCE(18);
      if (lookahead == ']') ADVANCE(119);
      if (lookahead == '\t' ||
          lookahead == ' ') SKIP(1)
      if ((11 <= lookahead && lookahead <= '\r')) SKIP(2)
      END_STATE();
    case 2:
      if (lookahead == '\n') SKIP(1)
      if (lookahead == '/') ADVANCE(127);
      if (lookahead == '@') ADVANCE(18);
      if (lookahead == ']') ADVANCE(119);
      if (('\t' <= lookahead && lookahead <= '\r') ||
          lookahead == ' ') SKIP(2)
      END_STATE();
    case 3:
      if (lookahead == '\n') SKIP(3)
      if (lookahead == '*') SKIP(3)
      if (lookahead == '/') ADVANCE(128);
      if (lookahead == '@') ADVANCE(17);
      if (lookahead == '[') ADVANCE(118);
      if (lookahead == '{') ADVANCE(22);
      if (lookahead == '\t' ||
          lookahead == ' ') SKIP(3)
      if ((11 <= lookahead && lookahead <= '\r')) SKIP(4)
      if (lookahead == '$' ||
          ('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(120);
      if (lookahead != 0 &&
          lookahead != '}') ADVANCE(126);
      END_STATE();
    case 4:
      if (lookahead == '\n') SKIP(3)
      if (lookahead == '/') ADVANCE(128);
      if (lookahead == '@') ADVANCE(17);
      if (lookahead == '[') ADVANCE(118);
      if (lookahead == '{') ADVANCE(22);
      if (('\t' <= lookahead && lookahead <= '\r') ||
          lookahead == ' ') SKIP(4)
      if (lookahead == '$' ||
          ('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(120);
      if (lookahead != 0 &&
          lookahead != '*' &&
          lookahead != '}') ADVANCE(126);
      END_STATE();
    case 5:
      if (lookahead == '\n') SKIP(5)
      if (lookahead == '#') ADVANCE(116);
      if (lookahead == '*') SKIP(5)
      if (lookahead == '.') ADVANCE(115);
      if (lookahead == '/') ADVANCE(128);
      if (lookahead == ':') ADVANCE(112);
      if (lookahead == '@') ADVANCE(17);
      if (lookahead == '~') ADVANCE(117);
      if (lookahead == '\t' ||
          lookahead == ' ') SKIP(5)
      if ((11 <= lookahead && lookahead <= '\r')) SKIP(6)
      if (lookahead != 0 &&
          lookahead != '{' &&
          lookahead != '}') ADVANCE(126);
      END_STATE();
    case 6:
      if (lookahead == '\n') SKIP(5)
      if (lookahead == '#') ADVANCE(116);
      if (lookahead == '.') ADVANCE(115);
      if (lookahead == '/') ADVANCE(128);
      if (lookahead == ':') ADVANCE(112);
      if (lookahead == '@') ADVANCE(17);
      if (lookahead == '~') ADVANCE(117);
      if (('\t' <= lookahead && lookahead <= '\r') ||
          lookahead == ' ') SKIP(6)
      if (lookahead != 0 &&
          lookahead != '*' &&
          lookahead != '{' &&
          lookahead != '}') ADVANCE(126);
      END_STATE();
    case 7:
      if (lookahead == '\n') SKIP(5)
      if (lookahead == '#') ADVANCE(116);
      if (lookahead == '.') ADVANCE(115);
      if (lookahead == '/') ADVANCE(113);
      if (lookahead == ':') ADVANCE(112);
      if (lookahead == '@') ADVANCE(17);
      if (lookahead == '~') ADVANCE(117);
      if (('\t' <= lookahead && lookahead <= '\r') ||
          lookahead == ' ') SKIP(6)
      if (lookahead != 0 &&
          lookahead != '*' &&
          lookahead != '{' &&
          lookahead != '}') ADVANCE(126);
      END_STATE();
    case 8:
      if (lookahead == '\n') SKIP(8)
      if (lookahead == '#') ADVANCE(116);
      if (lookahead == '*') SKIP(8)
      if (lookahead == '.') ADVANCE(115);
      if (lookahead == '/') ADVANCE(128);
      if (lookahead == '@') ADVANCE(17);
      if (lookahead == '~') ADVANCE(117);
      if (lookahead == '\t' ||
          lookahead == ' ') SKIP(8)
      if ((11 <= lookahead && lookahead <= '\r')) SKIP(9)
      if (lookahead != 0 &&
          lookahead != '{' &&
          lookahead != '}') ADVANCE(126);
      END_STATE();
    case 9:
      if (lookahead == '\n') SKIP(8)
      if (lookahead == '#') ADVANCE(116);
      if (lookahead == '.') ADVANCE(115);
      if (lookahead == '/') ADVANCE(128);
      if (lookahead == '@') ADVANCE(17);
      if (lookahead == '~') ADVANCE(117);
      if (('\t' <= lookahead && lookahead <= '\r') ||
          lookahead == ' ') SKIP(9)
      if (lookahead != 0 &&
          lookahead != '*' &&
          lookahead != '{' &&
          lookahead != '}') ADVANCE(126);
      END_STATE();
    case 10:
      if (lookahead == '\n') SKIP(10)
      if (lookahead == '*') SKIP(10)
      if (lookahead == '/') ADVANCE(128);
      if (lookahead == '@') ADVANCE(17);
      if (lookahead == '{') ADVANCE(22);
      if (lookahead == '\t' ||
          lookahead == ' ') SKIP(10)
      if ((11 <= lookahead && lookahead <= '\r')) SKIP(11)
      if (lookahead != 0 &&
          lookahead != '}') ADVANCE(126);
      END_STATE();
    case 11:
      if (lookahead == '\n') SKIP(10)
      if (lookahead == '/') ADVANCE(128);
      if (lookahead == '@') ADVANCE(17);
      if (lookahead == '{') ADVANCE(22);
      if (('\t' <= lookahead && lookahead <= '\r') ||
          lookahead == ' ') SKIP(11)
      if (lookahead != 0 &&
          lookahead != '*' &&
          lookahead != '}') ADVANCE(126);
      END_STATE();
    case 12:
      if (lookahead == '\n') SKIP(12)
      if (lookahead == '*') SKIP(12)
      if (lookahead == '{') ADVANCE(22);
      if (lookahead == '}') ADVANCE(23);
      if (lookahead == '\t' ||
          lookahead == ' ') SKIP(12)
      if ((11 <= lookahead && lookahead <= '\r')) SKIP(13)
      if (lookahead != 0 &&
          lookahead != '@') ADVANCE(126);
      END_STATE();
    case 13:
      if (lookahead == '\n') SKIP(12)
      if (lookahead == '{') ADVANCE(22);
      if (lookahead == '}') ADVANCE(23);
      if (('\t' <= lookahead && lookahead <= '\r') ||
          lookahead == ' ') SKIP(13)
      if (lookahead != 0 &&
          lookahead != '*' &&
          lookahead != '@') ADVANCE(126);
      END_STATE();
    case 14:
      if (lookahead == '\n') SKIP(14)
      if (lookahead == '*') ADVANCE(121);
      if (lookahead == '\t' ||
          lookahead == ' ') ADVANCE(121);
      if ((11 <= lookahead && lookahead <= '\r')) ADVANCE(122);
      if (lookahead != 0 &&
          lookahead != '}') ADVANCE(123);
      END_STATE();
    case 15:
      if (lookahead == '\n') SKIP(14)
      if (('\t' <= lookahead && lookahead <= '\r') ||
          lookahead == ' ') ADVANCE(122);
      if (lookahead != 0 &&
          lookahead != '}') ADVANCE(123);
      END_STATE();
    case 16:
      if (lookahead == '*') ADVANCE(125);
      if (lookahead != 0 &&
          lookahead != '\n' &&
          lookahead != '{' &&
          lookahead != '}') ADVANCE(16);
      END_STATE();
    case 17:
      if (lookahead == 'a') ADVANCE(37);
      if (lookahead == 'b') ADVANCE(73);
      if (lookahead == 'c') ADVANCE(28);
      if (lookahead == 'e') ADVANCE(106);
      if (lookahead == 'f') ADVANCE(57);
      if (lookahead == 'm') ADVANCE(54);
      if (lookahead == 'n') ADVANCE(29);
      if (lookahead == 'p') ADVANCE(32);
      if (lookahead == 'r') ADVANCE(43);
      if (lookahead == 't') ADVANCE(53);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('d' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 18:
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 19:
      if (eof) ADVANCE(21);
      if (lookahead == '\n') SKIP(19)
      if (lookahead == '#') ADVANCE(116);
      if (lookahead == '*') SKIP(19)
      if (lookahead == '.') ADVANCE(115);
      if (lookahead == '/') ADVANCE(129);
      if (lookahead == ':') ADVANCE(112);
      if (lookahead == '@') ADVANCE(17);
      if (lookahead == '[') ADVANCE(118);
      if (lookahead == ']') ADVANCE(119);
      if (lookahead == '{') ADVANCE(22);
      if (lookahead == '}') ADVANCE(23);
      if (lookahead == '~') ADVANCE(117);
      if (lookahead == '\t' ||
          lookahead == ' ') SKIP(19)
      if ((11 <= lookahead && lookahead <= '\r')) SKIP(20)
      if (lookahead == '$' ||
          ('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(120);
      if (lookahead != 0) ADVANCE(126);
      END_STATE();
    case 20:
      if (eof) ADVANCE(21);
      if (lookahead == '\n') SKIP(19)
      if (lookahead == '#') ADVANCE(116);
      if (lookahead == '.') ADVANCE(115);
      if (lookahead == '/') ADVANCE(129);
      if (lookahead == ':') ADVANCE(112);
      if (lookahead == '@') ADVANCE(17);
      if (lookahead == '[') ADVANCE(118);
      if (lookahead == ']') ADVANCE(119);
      if (lookahead == '{') ADVANCE(22);
      if (lookahead == '}') ADVANCE(23);
      if (lookahead == '~') ADVANCE(117);
      if (('\t' <= lookahead && lookahead <= '\r') ||
          lookahead == ' ') SKIP(20)
      if (lookahead == '$' ||
          ('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(120);
      if (lookahead != 0 &&
          lookahead != '*') ADVANCE(126);
      END_STATE();
    case 21:
      ACCEPT_TOKEN(ts_builtin_sym_end);
      END_STATE();
    case 22:
      ACCEPT_TOKEN(anon_sym_LBRACE);
      END_STATE();
    case 23:
      ACCEPT_TOKEN(anon_sym_RBRACE);
      END_STATE();
    case 24:
      ACCEPT_TOKEN(sym_tag_name_with_argument);
      if (lookahead == 's') ADVANCE(80);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 25:
      ACCEPT_TOKEN(sym_tag_name_with_argument);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 26:
      ACCEPT_TOKEN(sym_tag_name_with_type);
      if (lookahead == 's') ADVANCE(27);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 27:
      ACCEPT_TOKEN(sym_tag_name_with_type);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 28:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'a') ADVANCE(62);
      if (lookahead == 'o') ADVANCE(67);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('b' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 29:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'a') ADVANCE(64);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('b' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 30:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'a') ADVANCE(63);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('b' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 31:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'a') ADVANCE(38);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('b' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 32:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'a') ADVANCE(93);
      if (lookahead == 'r') ADVANCE(74);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('b' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 33:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'a') ADVANCE(60);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('b' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 34:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'a') ADVANCE(94);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('b' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 35:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'a') ADVANCE(41);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('b' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 36:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'b') ADVANCE(31);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 37:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'c') ADVANCE(39);
      if (lookahead == 'l') ADVANCE(56);
      if (lookahead == 'p') ADVANCE(55);
      if (lookahead == 'u') ADVANCE(52);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 38:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'c') ADVANCE(59);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 39:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'c') ADVANCE(46);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 40:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'c') ADVANCE(101);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 41:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'c') ADVANCE(44);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 42:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'c') ADVANCE(103);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 43:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'e') ADVANCE(98);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 44:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'e') ADVANCE(25);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 45:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'e') ADVANCE(24);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 46:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'e') ADVANCE(96);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 47:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'e') ADVANCE(70);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 48:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'e') ADVANCE(94);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 49:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'e') ADVANCE(87);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 50:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'e') ADVANCE(92);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 51:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'e') ADVANCE(72);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 52:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'g') ADVANCE(65);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 53:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'h') ADVANCE(85);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 54:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'i') ADVANCE(109);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 55:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'i') ADVANCE(25);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 56:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'i') ADVANCE(34);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 57:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'i') ADVANCE(88);
      if (lookahead == 'u') ADVANCE(69);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 58:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'i') ADVANCE(78);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 59:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'k') ADVANCE(25);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 60:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'l') ADVANCE(25);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 61:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'l') ADVANCE(36);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 62:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'l') ADVANCE(61);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 63:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'm') ADVANCE(25);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 64:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'm') ADVANCE(45);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 65:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'm') ADVANCE(51);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 66:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'n') ADVANCE(25);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 67:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'n') ADVANCE(95);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 68:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'n') ADVANCE(26);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 69:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'n') ADVANCE(40);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 70:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'n') ADVANCE(97);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 71:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'n') ADVANCE(33);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 72:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'n') ADVANCE(100);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 73:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'o') ADVANCE(89);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 74:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'o') ADVANCE(82);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 75:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'o') ADVANCE(107);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 76:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'o') ADVANCE(108);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 77:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'o') ADVANCE(91);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 78:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'o') ADVANCE(66);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 79:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'o') ADVANCE(83);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 80:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'p') ADVANCE(35);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 81:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'p') ADVANCE(77);
      if (lookahead == 't') ADVANCE(49);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 82:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'p') ADVANCE(50);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 83:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'r') ADVANCE(25);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 84:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'r') ADVANCE(105);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 85:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'r') ADVANCE(75);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 86:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'r') ADVANCE(76);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 87:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'r') ADVANCE(71);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 88:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'r') ADVANCE(48);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 89:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'r') ADVANCE(86);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 90:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'r') ADVANCE(68);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 91:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'r') ADVANCE(100);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 92:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'r') ADVANCE(99);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 93:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'r') ADVANCE(30);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 94:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 's') ADVANCE(25);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 95:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 's') ADVANCE(102);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 96:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 's') ADVANCE(94);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 97:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 't') ADVANCE(25);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 98:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 't') ADVANCE(104);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 99:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 't') ADVANCE(110);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 100:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 't') ADVANCE(94);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 101:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 't') ADVANCE(58);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 102:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 't') ADVANCE(84);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 103:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 't') ADVANCE(79);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 104:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'u') ADVANCE(90);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 105:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'u') ADVANCE(42);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 106:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'v') ADVANCE(47);
      if (lookahead == 'x') ADVANCE(81);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 107:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'w') ADVANCE(26);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 108:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'w') ADVANCE(94);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 109:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'x') ADVANCE(48);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 110:
      ACCEPT_TOKEN(sym_tag_name);
      if (lookahead == 'y') ADVANCE(25);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 111:
      ACCEPT_TOKEN(sym_tag_name);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(111);
      END_STATE();
    case 112:
      ACCEPT_TOKEN(anon_sym_COLON);
      END_STATE();
    case 113:
      ACCEPT_TOKEN(anon_sym_SLASH);
      END_STATE();
    case 114:
      ACCEPT_TOKEN(anon_sym_SLASH);
      if (lookahead == '*') ADVANCE(127);
      END_STATE();
    case 115:
      ACCEPT_TOKEN(anon_sym_DOT);
      END_STATE();
    case 116:
      ACCEPT_TOKEN(anon_sym_POUND);
      END_STATE();
    case 117:
      ACCEPT_TOKEN(anon_sym_TILDE);
      END_STATE();
    case 118:
      ACCEPT_TOKEN(anon_sym_LBRACK);
      END_STATE();
    case 119:
      ACCEPT_TOKEN(anon_sym_RBRACK);
      END_STATE();
    case 120:
      ACCEPT_TOKEN(sym_identifier);
      if (lookahead == '$' ||
          ('0' <= lookahead && lookahead <= '9') ||
          ('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(120);
      END_STATE();
    case 121:
      ACCEPT_TOKEN(sym_type);
      if (lookahead == '*') ADVANCE(121);
      if (lookahead == '\t' ||
          lookahead == ' ') ADVANCE(121);
      if ((11 <= lookahead && lookahead <= '\r')) ADVANCE(122);
      if (lookahead != 0 &&
          lookahead != '\n' &&
          lookahead != '}') ADVANCE(123);
      END_STATE();
    case 122:
      ACCEPT_TOKEN(sym_type);
      if (lookahead == '\t' ||
          (11 <= lookahead && lookahead <= '\r') ||
          lookahead == ' ') ADVANCE(122);
      if (lookahead != 0 &&
          lookahead != '\n' &&
          lookahead != '}') ADVANCE(123);
      END_STATE();
    case 123:
      ACCEPT_TOKEN(sym_type);
      if (lookahead != 0 &&
          lookahead != '\n' &&
          lookahead != '}') ADVANCE(123);
      END_STATE();
    case 124:
      ACCEPT_TOKEN(sym__text);
      if (lookahead == '*') ADVANCE(125);
      if (lookahead == '/') ADVANCE(124);
      if (lookahead != 0 &&
          lookahead != '\n' &&
          lookahead != '{' &&
          lookahead != '}') ADVANCE(124);
      END_STATE();
    case 125:
      ACCEPT_TOKEN(sym__text);
      if (lookahead == '*') ADVANCE(125);
      if (lookahead != 0 &&
          lookahead != '\n' &&
          lookahead != '/' &&
          lookahead != '{' &&
          lookahead != '}') ADVANCE(16);
      END_STATE();
    case 126:
      ACCEPT_TOKEN(sym__text);
      if (lookahead == '/') ADVANCE(126);
      if (lookahead != 0 &&
          lookahead != '\n' &&
          lookahead != '*' &&
          lookahead != '{' &&
          lookahead != '}') ADVANCE(124);
      END_STATE();
    case 127:
      ACCEPT_TOKEN(sym__begin);
      if (lookahead == '*') ADVANCE(127);
      END_STATE();
    case 128:
      ACCEPT_TOKEN(sym__end);
      END_STATE();
    case 129:
      ACCEPT_TOKEN(sym__end);
      if (lookahead == '*') ADVANCE(127);
      END_STATE();
    default:
      return false;
  }
}

static const TSLexMode ts_lex_modes[STATE_COUNT] = {
  [0] = {.lex_state = 0},
  [1] = {.lex_state = 2},
  [2] = {.lex_state = 4},
  [3] = {.lex_state = 4},
  [4] = {.lex_state = 7},
  [5] = {.lex_state = 6},
  [6] = {.lex_state = 9},
  [7] = {.lex_state = 9},
  [8] = {.lex_state = 11},
  [9] = {.lex_state = 11},
  [10] = {.lex_state = 9},
  [11] = {.lex_state = 11},
  [12] = {.lex_state = 9},
  [13] = {.lex_state = 9},
  [14] = {.lex_state = 9},
  [15] = {.lex_state = 11},
  [16] = {.lex_state = 11},
  [17] = {.lex_state = 0},
  [18] = {.lex_state = 4},
  [19] = {.lex_state = 4},
  [20] = {.lex_state = 4},
  [21] = {.lex_state = 11},
  [22] = {.lex_state = 4},
  [23] = {.lex_state = 11},
  [24] = {.lex_state = 11},
  [25] = {.lex_state = 13},
  [26] = {.lex_state = 13},
  [27] = {.lex_state = 13},
  [28] = {.lex_state = 4},
  [29] = {.lex_state = 4},
  [30] = {.lex_state = 4},
  [31] = {.lex_state = 4},
  [32] = {.lex_state = 13},
  [33] = {.lex_state = 13},
  [34] = {.lex_state = 0},
  [35] = {.lex_state = 13},
  [36] = {.lex_state = 15},
  [37] = {.lex_state = 0},
  [38] = {.lex_state = 0},
  [39] = {.lex_state = 0},
  [40] = {.lex_state = 0},
  [41] = {.lex_state = 0},
  [42] = {.lex_state = 2},
  [43] = {.lex_state = 0},
  [44] = {.lex_state = 0},
  [45] = {.lex_state = 2},
  [46] = {.lex_state = 15},
  [47] = {.lex_state = 0},
  [48] = {.lex_state = 0},
  [49] = {.lex_state = 0},
  [50] = {.lex_state = 2},
};

static const uint16_t ts_parse_table[LARGE_STATE_COUNT][SYMBOL_COUNT] = {
  [0] = {
    [ts_builtin_sym_end] = ACTIONS(1),
    [anon_sym_LBRACE] = ACTIONS(1),
    [anon_sym_RBRACE] = ACTIONS(1),
    [sym_tag_name_with_argument] = ACTIONS(1),
    [sym_tag_name_with_type] = ACTIONS(1),
    [sym_tag_name] = ACTIONS(1),
    [anon_sym_COLON] = ACTIONS(1),
    [anon_sym_SLASH] = ACTIONS(1),
    [anon_sym_DOT] = ACTIONS(1),
    [anon_sym_POUND] = ACTIONS(1),
    [anon_sym_TILDE] = ACTIONS(1),
    [anon_sym_LBRACK] = ACTIONS(1),
    [anon_sym_RBRACK] = ACTIONS(1),
    [sym_identifier] = ACTIONS(1),
    [sym__text] = ACTIONS(1),
    [sym__begin] = ACTIONS(1),
    [sym__end] = ACTIONS(1),
  },
  [1] = {
    [sym_document] = STATE(40),
    [sym__begin] = ACTIONS(3),
  },
};

static const uint16_t ts_small_parse_table[] = {
  [0] = 8,
    ACTIONS(5), 1,
      anon_sym_LBRACE,
    ACTIONS(9), 1,
      anon_sym_LBRACK,
    ACTIONS(11), 1,
      sym_identifier,
    ACTIONS(13), 1,
      sym__text,
    ACTIONS(15), 1,
      sym__end,
    STATE(31), 1,
      sym_description,
    ACTIONS(7), 3,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
    STATE(6), 5,
      sym__expression,
      sym_qualified_expression,
      sym_path_expression,
      sym_member_expression,
      sym_optional_identifier,
  [31] = 7,
    ACTIONS(9), 1,
      anon_sym_LBRACK,
    ACTIONS(11), 1,
      sym_identifier,
    ACTIONS(13), 1,
      sym__text,
    ACTIONS(19), 1,
      sym__end,
    STATE(29), 1,
      sym_description,
    ACTIONS(17), 3,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
    STATE(7), 5,
      sym__expression,
      sym_qualified_expression,
      sym_path_expression,
      sym_member_expression,
      sym_optional_identifier,
  [59] = 4,
    ACTIONS(23), 1,
      anon_sym_COLON,
    ACTIONS(25), 1,
      anon_sym_SLASH,
    ACTIONS(27), 3,
      anon_sym_DOT,
      anon_sym_POUND,
      anon_sym_TILDE,
    ACTIONS(21), 5,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
      sym__text,
      sym__end,
  [78] = 3,
    ACTIONS(23), 1,
      anon_sym_COLON,
    ACTIONS(29), 4,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
      sym__text,
    ACTIONS(31), 4,
      anon_sym_DOT,
      anon_sym_POUND,
      anon_sym_TILDE,
      sym__end,
  [94] = 5,
    ACTIONS(13), 1,
      sym__text,
    ACTIONS(37), 1,
      sym__end,
    STATE(30), 1,
      sym_description,
    ACTIONS(33), 3,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
    ACTIONS(35), 3,
      anon_sym_DOT,
      anon_sym_POUND,
      anon_sym_TILDE,
  [114] = 5,
    ACTIONS(13), 1,
      sym__text,
    ACTIONS(41), 1,
      sym__end,
    STATE(28), 1,
      sym_description,
    ACTIONS(35), 3,
      anon_sym_DOT,
      anon_sym_POUND,
      anon_sym_TILDE,
    ACTIONS(39), 3,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
  [134] = 5,
    ACTIONS(43), 1,
      anon_sym_LBRACE,
    ACTIONS(47), 1,
      sym__text,
    ACTIONS(49), 1,
      sym__end,
    STATE(15), 2,
      sym_inline_tag,
      aux_sym_description_repeat1,
    ACTIONS(45), 3,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
  [153] = 7,
    ACTIONS(13), 1,
      sym__text,
    ACTIONS(51), 1,
      sym_tag_name_with_argument,
    ACTIONS(53), 1,
      sym_tag_name_with_type,
    ACTIONS(55), 1,
      sym_tag_name,
    ACTIONS(57), 1,
      sym__end,
    STATE(18), 1,
      sym_description,
    STATE(22), 2,
      sym_tag,
      aux_sym_document_repeat1,
  [176] = 2,
    ACTIONS(29), 4,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
      sym__text,
    ACTIONS(31), 4,
      anon_sym_DOT,
      anon_sym_POUND,
      anon_sym_TILDE,
      sym__end,
  [189] = 5,
    ACTIONS(43), 1,
      anon_sym_LBRACE,
    ACTIONS(61), 1,
      sym__text,
    ACTIONS(63), 1,
      sym__end,
    STATE(8), 2,
      sym_inline_tag,
      aux_sym_description_repeat1,
    ACTIONS(59), 3,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
  [208] = 2,
    ACTIONS(65), 4,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
      sym__text,
    ACTIONS(67), 4,
      anon_sym_DOT,
      anon_sym_POUND,
      anon_sym_TILDE,
      sym__end,
  [221] = 2,
    ACTIONS(69), 4,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
      sym__text,
    ACTIONS(71), 4,
      anon_sym_DOT,
      anon_sym_POUND,
      anon_sym_TILDE,
      sym__end,
  [234] = 2,
    ACTIONS(73), 4,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
      sym__text,
    ACTIONS(75), 4,
      anon_sym_DOT,
      anon_sym_POUND,
      anon_sym_TILDE,
      sym__end,
  [247] = 5,
    ACTIONS(77), 1,
      anon_sym_LBRACE,
    ACTIONS(82), 1,
      sym__text,
    ACTIONS(85), 1,
      sym__end,
    STATE(15), 2,
      sym_inline_tag,
      aux_sym_description_repeat1,
    ACTIONS(80), 3,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
  [266] = 5,
    ACTIONS(13), 1,
      sym__text,
    ACTIONS(15), 1,
      sym__end,
    ACTIONS(87), 1,
      anon_sym_LBRACE,
    STATE(31), 1,
      sym_description,
    ACTIONS(7), 3,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
  [284] = 3,
    ACTIONS(9), 1,
      anon_sym_LBRACK,
    ACTIONS(11), 1,
      sym_identifier,
    STATE(13), 5,
      sym__expression,
      sym_qualified_expression,
      sym_path_expression,
      sym_member_expression,
      sym_optional_identifier,
  [298] = 5,
    ACTIONS(51), 1,
      sym_tag_name_with_argument,
    ACTIONS(53), 1,
      sym_tag_name_with_type,
    ACTIONS(55), 1,
      sym_tag_name,
    ACTIONS(89), 1,
      sym__end,
    STATE(19), 2,
      sym_tag,
      aux_sym_document_repeat1,
  [315] = 5,
    ACTIONS(51), 1,
      sym_tag_name_with_argument,
    ACTIONS(53), 1,
      sym_tag_name_with_type,
    ACTIONS(55), 1,
      sym_tag_name,
    ACTIONS(91), 1,
      sym__end,
    STATE(20), 2,
      sym_tag,
      aux_sym_document_repeat1,
  [332] = 5,
    ACTIONS(93), 1,
      sym_tag_name_with_argument,
    ACTIONS(96), 1,
      sym_tag_name_with_type,
    ACTIONS(99), 1,
      sym_tag_name,
    ACTIONS(102), 1,
      sym__end,
    STATE(20), 2,
      sym_tag,
      aux_sym_document_repeat1,
  [349] = 2,
    ACTIONS(104), 2,
      anon_sym_LBRACE,
      sym__end,
    ACTIONS(106), 4,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
      sym__text,
  [360] = 5,
    ACTIONS(51), 1,
      sym_tag_name_with_argument,
    ACTIONS(53), 1,
      sym_tag_name_with_type,
    ACTIONS(55), 1,
      sym_tag_name,
    ACTIONS(89), 1,
      sym__end,
    STATE(20), 2,
      sym_tag,
      aux_sym_document_repeat1,
  [377] = 4,
    ACTIONS(13), 1,
      sym__text,
    ACTIONS(19), 1,
      sym__end,
    STATE(29), 1,
      sym_description,
    ACTIONS(17), 3,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
  [392] = 4,
    ACTIONS(13), 1,
      sym__text,
    ACTIONS(15), 1,
      sym__end,
    STATE(31), 1,
      sym_description,
    ACTIONS(7), 3,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
  [407] = 4,
    ACTIONS(63), 1,
      anon_sym_RBRACE,
    ACTIONS(108), 1,
      anon_sym_LBRACE,
    ACTIONS(110), 1,
      sym__text,
    STATE(26), 2,
      sym_inline_tag,
      aux_sym_description_repeat1,
  [421] = 4,
    ACTIONS(49), 1,
      anon_sym_RBRACE,
    ACTIONS(108), 1,
      anon_sym_LBRACE,
    ACTIONS(112), 1,
      sym__text,
    STATE(27), 2,
      sym_inline_tag,
      aux_sym_description_repeat1,
  [435] = 4,
    ACTIONS(85), 1,
      anon_sym_RBRACE,
    ACTIONS(114), 1,
      anon_sym_LBRACE,
    ACTIONS(117), 1,
      sym__text,
    STATE(27), 2,
      sym_inline_tag,
      aux_sym_description_repeat1,
  [449] = 2,
    ACTIONS(122), 1,
      sym__end,
    ACTIONS(120), 3,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
  [458] = 2,
    ACTIONS(41), 1,
      sym__end,
    ACTIONS(39), 3,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
  [467] = 2,
    ACTIONS(126), 1,
      sym__end,
    ACTIONS(124), 3,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
  [476] = 2,
    ACTIONS(37), 1,
      sym__end,
    ACTIONS(33), 3,
      sym_tag_name_with_argument,
      sym_tag_name_with_type,
      sym_tag_name,
  [485] = 1,
    ACTIONS(104), 3,
      anon_sym_LBRACE,
      anon_sym_RBRACE,
      sym__text,
  [491] = 2,
    ACTIONS(128), 1,
      sym__text,
    STATE(48), 1,
      sym_description,
  [498] = 2,
    ACTIONS(130), 1,
      sym_identifier,
    STATE(10), 1,
      sym_qualified_expression,
  [505] = 2,
    ACTIONS(128), 1,
      sym__text,
    STATE(39), 1,
      sym_description,
  [512] = 1,
    ACTIONS(132), 1,
      sym_type,
  [516] = 1,
    ACTIONS(134), 1,
      ts_builtin_sym_end,
  [520] = 1,
    ACTIONS(136), 1,
      anon_sym_RBRACE,
  [524] = 1,
    ACTIONS(138), 1,
      anon_sym_RBRACE,
  [528] = 1,
    ACTIONS(140), 1,
      ts_builtin_sym_end,
  [532] = 1,
    ACTIONS(142), 1,
      sym_identifier,
  [536] = 1,
    ACTIONS(144), 1,
      anon_sym_RBRACK,
  [540] = 1,
    ACTIONS(146), 1,
      anon_sym_RBRACE,
  [544] = 1,
    ACTIONS(148), 1,
      ts_builtin_sym_end,
  [548] = 1,
    ACTIONS(150), 1,
      sym_tag_name,
  [552] = 1,
    ACTIONS(152), 1,
      sym_type,
  [556] = 1,
    ACTIONS(154), 1,
      sym_identifier,
  [560] = 1,
    ACTIONS(156), 1,
      anon_sym_RBRACE,
  [564] = 1,
    ACTIONS(158), 1,
      ts_builtin_sym_end,
  [568] = 1,
    ACTIONS(160), 1,
      sym_tag_name,
};

static const uint32_t ts_small_parse_table_map[] = {
  [SMALL_STATE(2)] = 0,
  [SMALL_STATE(3)] = 31,
  [SMALL_STATE(4)] = 59,
  [SMALL_STATE(5)] = 78,
  [SMALL_STATE(6)] = 94,
  [SMALL_STATE(7)] = 114,
  [SMALL_STATE(8)] = 134,
  [SMALL_STATE(9)] = 153,
  [SMALL_STATE(10)] = 176,
  [SMALL_STATE(11)] = 189,
  [SMALL_STATE(12)] = 208,
  [SMALL_STATE(13)] = 221,
  [SMALL_STATE(14)] = 234,
  [SMALL_STATE(15)] = 247,
  [SMALL_STATE(16)] = 266,
  [SMALL_STATE(17)] = 284,
  [SMALL_STATE(18)] = 298,
  [SMALL_STATE(19)] = 315,
  [SMALL_STATE(20)] = 332,
  [SMALL_STATE(21)] = 349,
  [SMALL_STATE(22)] = 360,
  [SMALL_STATE(23)] = 377,
  [SMALL_STATE(24)] = 392,
  [SMALL_STATE(25)] = 407,
  [SMALL_STATE(26)] = 421,
  [SMALL_STATE(27)] = 435,
  [SMALL_STATE(28)] = 449,
  [SMALL_STATE(29)] = 458,
  [SMALL_STATE(30)] = 467,
  [SMALL_STATE(31)] = 476,
  [SMALL_STATE(32)] = 485,
  [SMALL_STATE(33)] = 491,
  [SMALL_STATE(34)] = 498,
  [SMALL_STATE(35)] = 505,
  [SMALL_STATE(36)] = 512,
  [SMALL_STATE(37)] = 516,
  [SMALL_STATE(38)] = 520,
  [SMALL_STATE(39)] = 524,
  [SMALL_STATE(40)] = 528,
  [SMALL_STATE(41)] = 532,
  [SMALL_STATE(42)] = 536,
  [SMALL_STATE(43)] = 540,
  [SMALL_STATE(44)] = 544,
  [SMALL_STATE(45)] = 548,
  [SMALL_STATE(46)] = 552,
  [SMALL_STATE(47)] = 556,
  [SMALL_STATE(48)] = 560,
  [SMALL_STATE(49)] = 564,
  [SMALL_STATE(50)] = 568,
};

static const TSParseActionEntry ts_parse_actions[] = {
  [0] = {.entry = {.count = 0, .reusable = false}},
  [1] = {.entry = {.count = 1, .reusable = false}}, RECOVER(),
  [3] = {.entry = {.count = 1, .reusable = true}}, SHIFT(9),
  [5] = {.entry = {.count = 1, .reusable = true}}, SHIFT(36),
  [7] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_tag, 1),
  [9] = {.entry = {.count = 1, .reusable = true}}, SHIFT(47),
  [11] = {.entry = {.count = 1, .reusable = true}}, SHIFT(4),
  [13] = {.entry = {.count = 1, .reusable = false}}, SHIFT(11),
  [15] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_tag, 1),
  [17] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_tag, 4),
  [19] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_tag, 4),
  [21] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym__expression, 1),
  [23] = {.entry = {.count = 1, .reusable = true}}, SHIFT(17),
  [25] = {.entry = {.count = 1, .reusable = true}}, SHIFT(41),
  [27] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym__expression, 1),
  [29] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_member_expression, 3),
  [31] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_member_expression, 3),
  [33] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_tag, 2),
  [35] = {.entry = {.count = 1, .reusable = true}}, SHIFT(34),
  [37] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_tag, 2),
  [39] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_tag, 5),
  [41] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_tag, 5),
  [43] = {.entry = {.count = 1, .reusable = true}}, SHIFT(45),
  [45] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_description, 2),
  [47] = {.entry = {.count = 1, .reusable = false}}, SHIFT(15),
  [49] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_description, 2),
  [51] = {.entry = {.count = 1, .reusable = false}}, SHIFT(2),
  [53] = {.entry = {.count = 1, .reusable = false}}, SHIFT(16),
  [55] = {.entry = {.count = 1, .reusable = false}}, SHIFT(24),
  [57] = {.entry = {.count = 1, .reusable = true}}, SHIFT(49),
  [59] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_description, 1),
  [61] = {.entry = {.count = 1, .reusable = false}}, SHIFT(8),
  [63] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_description, 1),
  [65] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_path_expression, 3),
  [67] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_path_expression, 3),
  [69] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_qualified_expression, 3),
  [71] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_qualified_expression, 3),
  [73] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_optional_identifier, 3),
  [75] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_optional_identifier, 3),
  [77] = {.entry = {.count = 2, .reusable = true}}, REDUCE(aux_sym_description_repeat1, 2), SHIFT_REPEAT(45),
  [80] = {.entry = {.count = 1, .reusable = false}}, REDUCE(aux_sym_description_repeat1, 2),
  [82] = {.entry = {.count = 2, .reusable = false}}, REDUCE(aux_sym_description_repeat1, 2), SHIFT_REPEAT(15),
  [85] = {.entry = {.count = 1, .reusable = true}}, REDUCE(aux_sym_description_repeat1, 2),
  [87] = {.entry = {.count = 1, .reusable = true}}, SHIFT(46),
  [89] = {.entry = {.count = 1, .reusable = true}}, SHIFT(44),
  [91] = {.entry = {.count = 1, .reusable = true}}, SHIFT(37),
  [93] = {.entry = {.count = 2, .reusable = false}}, REDUCE(aux_sym_document_repeat1, 2), SHIFT_REPEAT(2),
  [96] = {.entry = {.count = 2, .reusable = false}}, REDUCE(aux_sym_document_repeat1, 2), SHIFT_REPEAT(16),
  [99] = {.entry = {.count = 2, .reusable = false}}, REDUCE(aux_sym_document_repeat1, 2), SHIFT_REPEAT(24),
  [102] = {.entry = {.count = 1, .reusable = true}}, REDUCE(aux_sym_document_repeat1, 2),
  [104] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_inline_tag, 4),
  [106] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_inline_tag, 4),
  [108] = {.entry = {.count = 1, .reusable = true}}, SHIFT(50),
  [110] = {.entry = {.count = 1, .reusable = true}}, SHIFT(26),
  [112] = {.entry = {.count = 1, .reusable = true}}, SHIFT(27),
  [114] = {.entry = {.count = 2, .reusable = true}}, REDUCE(aux_sym_description_repeat1, 2), SHIFT_REPEAT(50),
  [117] = {.entry = {.count = 2, .reusable = true}}, REDUCE(aux_sym_description_repeat1, 2), SHIFT_REPEAT(27),
  [120] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_tag, 6),
  [122] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_tag, 6),
  [124] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_tag, 3),
  [126] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_tag, 3),
  [128] = {.entry = {.count = 1, .reusable = true}}, SHIFT(25),
  [130] = {.entry = {.count = 1, .reusable = true}}, SHIFT(5),
  [132] = {.entry = {.count = 1, .reusable = true}}, SHIFT(43),
  [134] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_document, 4),
  [136] = {.entry = {.count = 1, .reusable = true}}, SHIFT(23),
  [138] = {.entry = {.count = 1, .reusable = true}}, SHIFT(21),
  [140] = {.entry = {.count = 1, .reusable = true}},  ACCEPT_INPUT(),
  [142] = {.entry = {.count = 1, .reusable = true}}, SHIFT(12),
  [144] = {.entry = {.count = 1, .reusable = true}}, SHIFT(14),
  [146] = {.entry = {.count = 1, .reusable = true}}, SHIFT(3),
  [148] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_document, 3),
  [150] = {.entry = {.count = 1, .reusable = true}}, SHIFT(35),
  [152] = {.entry = {.count = 1, .reusable = true}}, SHIFT(38),
  [154] = {.entry = {.count = 1, .reusable = true}}, SHIFT(42),
  [156] = {.entry = {.count = 1, .reusable = true}}, SHIFT(32),
  [158] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_document, 2),
  [160] = {.entry = {.count = 1, .reusable = true}}, SHIFT(33),
};

#ifdef __cplusplus
extern "C" {
#endif
#ifdef _WIN32
#define extern __declspec(dllexport)
#endif

extern const TSLanguage *tree_sitter_jsdoc(void) {
  static const TSLanguage language = {
    .version = LANGUAGE_VERSION,
    .symbol_count = SYMBOL_COUNT,
    .alias_count = ALIAS_COUNT,
    .token_count = TOKEN_COUNT,
    .external_token_count = EXTERNAL_TOKEN_COUNT,
    .state_count = STATE_COUNT,
    .large_state_count = LARGE_STATE_COUNT,
    .production_id_count = PRODUCTION_ID_COUNT,
    .field_count = FIELD_COUNT,
    .max_alias_sequence_length = MAX_ALIAS_SEQUENCE_LENGTH,
    .parse_table = &ts_parse_table[0][0],
    .small_parse_table = ts_small_parse_table,
    .small_parse_table_map = ts_small_parse_table_map,
    .parse_actions = ts_parse_actions,
    .symbol_names = ts_symbol_names,
    .symbol_metadata = ts_symbol_metadata,
    .public_symbol_map = ts_symbol_map,
    .alias_map = ts_non_terminal_alias_map,
    .alias_sequences = &ts_alias_sequences[0][0],
    .lex_modes = ts_lex_modes,
    .lex_fn = ts_lex,
    .primary_state_ids = ts_primary_state_ids,
  };
  return &language;
}
#ifdef __cplusplus
}
#endif
