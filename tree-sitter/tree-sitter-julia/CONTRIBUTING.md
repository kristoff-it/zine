# Contributing guide

The two main ways to help the project are reporting and fixing bugs.


## Report bugs

To report a bug, you can file an [issue on gitHub](https://github.com/tree-sitter/tree-sitter-julia/issues).
If possible, the issue should include an brief explanation of the bug, the expected behavior, and a minimal reproducible example.

If your text editor isn't highlighting code correctly, the error might be in the editor or in the parser.
The best way to check if it's an error in the parser is to read the generated syntax tree of the erroneously highlighted code.
Some editors can display the syntax tree of a text file.
For example, Neovim has the [`:InspectTree`](https://neovim.io/doc/user/treesitter.html#vim.treesitter.inspect_tree()) command.

If the syntax tree has `ERROR` nodes for valid Julia programs, then you should file an issue here.
Otherwise, if the syntax tree appears to be correct, the issue might be with the queries used by the text editor.
In that case, you can file an issue in the corresponding issue tracker.


## Build and develop

tree-sitter-julia follows the usual structure of a tree-sitter project.
To get started, you should read the [Creating parsers](https://tree-sitter.github.io/tree-sitter/creating-parsers) section of the tree-sitter docs.

The grammar is mostly done feature-wise, but optimizations in build size and compilation speed are very welcome.
Currently the grammar takes a while to compile (about 1 minute).

Every new feature or bug fix should include tests. This helps us document supported syntax, check edge cases, and avoid regressions.


## Neovim specific details

The Julia queries used in Neovim are in the nvim-treesitter repository:
- [Queries](https://github.com/nvim-treesitter/nvim-treesitter/tree/master/queries/julia)
- [CONTRIBUTING.md](https://github.com/nvim-treesitter/nvim-treesitter/blob/master/CONTRIBUTING.md)

If you want to use your locally built Julia parser in Neovim, you can copy the following snippet
to your configuration _before_ you call `require('nvim-treesitter.configs').setup`.

```lua
require("nvim-treesitter.parsers").get_parser_configs().julia = {
  install_info = {
    url = "~/path/to/your/fork/of/tree-sitter-julia/",
    files = { "src/parser.c", "src/scanner.c" },
  }
}
```

You'll have to modify the tree-sitter queries according to the changes you've made in the grammar,
otherwise you might get highlighting errors.
