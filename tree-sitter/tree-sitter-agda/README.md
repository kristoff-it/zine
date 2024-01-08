# Agda Grammar for tree-sitter

[![Build Status](https://travis-ci.org/tree-sitter/tree-sitter-agda.svg?branch=master)](https://travis-ci.org/tree-sitter/tree-sitter-agda)

Syntax highlighting and code folding done right (with context-free grammar, finally!)

![tree-sitter](https://i.imgur.com/7Pfmqjv.png)

## How to contribute

* [documentation](http://tree-sitter.github.io/tree-sitter/)

Install dependencies:

```bash
npm install
```

To see if you have `tree-sitter` installed:

```bash
npx tree-sitter
```

To generate the parser:

```bash
npx tree-sitter generate
```

Run test to see if everything's okay:

```bash
npm test
```

You may wanna run this on the [language-agda](https://github.com/banacorn/language-agda)'s side:

```bash
npm install
apm rebuild
```
