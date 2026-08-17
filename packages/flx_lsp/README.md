# flx_lsp

Language server for [flx](https://github.com/sonalsithara/flx). Speaks LSP over
stdio; editors launch it, you generally should not.

```bash
dart pub global activate flx_lsp
```

For VS Code, install the extension from
[`tools/vscode-flx`](https://github.com/sonalsithara/flx/tree/main/tools/vscode-flx)
rather than wiring this up by hand.

## Features

| | |
| --- | --- |
| Syntax diagnostics | Per keystroke — same message, position and hint as the build |
| Type errors | On save, mapped back onto the `.flx` that produced them |
| Completion | Hooks, widgets, arguments, enum shorthands, `Icons`, local bindings, composables |
| Hover | Signatures and docs; the route for a `@page`; the expression behind a binding |
| Go to definition | Composables across files, bindings, parameters — including from inside `${…}` |
| Outline & workspace symbols | Composables with their bindings nested |

## The design constraint

The parser is fatally strict, and a file you are typing into does not parse —
`Column { ⟨cursor⟩ }` has an empty block, which is a syntax error. So
completion reads the **token stream**, never the AST, and falls back to a
truncated tokenization when even the lexer fails on a half-typed string.
Navigation and the outline use the last *successful* parse rather than
emptying themselves on every keystroke.

## Options

`initializationOptions.semanticDiagnostics: false` turns off the Dart analyzer
pass. It is on by default, and it **writes files**: type-checking requires
transpiling the folder on save, so generated `.dart` appears as a side effect.

## License

BSD-3-Clause.
