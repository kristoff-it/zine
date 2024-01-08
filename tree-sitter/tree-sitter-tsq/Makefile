.PHONY: all check

all: src/parser.c

check: src/parser.c
	tree-sitter test

src/parser.c: grammar.js
	tree-sitter generate
