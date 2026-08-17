<p align="center">
  <img src="https://raw.githubusercontent.com/sonal-sithara/flx/main/assets/flx-icon-128.png"
       width="96" alt="flx">
</p>

# flx — VS Code support

Syntax highlighting plus a language server: diagnostics, completion, hover,
go-to-definition and an outline for `.flx`.

## Install

```bash
npm install --prefix tools/vscode-flx
ln -s "$PWD/tools/vscode-flx" ~/.vscode/extensions/flx
```

Reload the window and open a `.flx` file. The status bar should read **flx**,
and the *flx* output channel should show the server starting.

By default the server runs from source with `dart run`, which takes a second
or two to start but always matches the checkout. For a faster start:

```bash
make lsp-build          # compiles packages/flx_lsp to a native executable
```

then point `flx.server.path` at the binary it prints.

## What you get

| Feature | Notes |
| --- | --- |
| Syntax diagnostics | Instant, on every keystroke, straight from flxc — same message, line, column and hint as the build |
| **Dart type errors** | On save. Reported against the `.flx` that produced them, not the generated `.dart` |
| Completion | Hooks, widgets, argument names, enum shorthands, `Icons`, local `val`s and composables |
| Hover | Signature and documentation for hooks and widgets; route for a `@page`; expression for a `val` |
| Go to definition | Composables across files, `val`s and parameters — including from inside `${...}` |
| **Into the Dart** | `useState` opens flx_runtime, `Button` its widget, `Text` opens Flutter, and your own classes open where you wrote them |
| Outline | Composables with their bindings nested, in the breadcrumb and symbol list |
| Workspace symbols | `Cmd-T` finds any composable by name |
| File icon | The Dart mark in flx violet, on `.flx` files in the explorer and tabs |

Completion works on files that **don't parse**, which is most of them while
you type. It reads the token stream rather than the AST.

The file icon is contributed against the language, which is the only hook VS
Code offers short of shipping an entire file icon theme. A file icon theme can
opt out of language icons with `showLanguageModeIcons: false`, and some do —
the default **Seti** theme shows the flx mark, the built-in **Modern Icons**
theme keeps its own generic file icon instead.

## Settings

| Setting | Default | Meaning |
| --- | --- | --- |
| `flx.server.path` | `""` | A compiled `flx_lsp` binary. Empty means run from source |
| `flx.server.packagePath` | `packages/flx_lsp` | Where the server package lives |
| `flx.semanticDiagnostics` | `true` | Report Dart type errors against `.flx` |
| `flx.trace.server` | `off` | Log LSP traffic to the output channel |

**`flx.semanticDiagnostics` writes files.** To type-check, the server has to
transpile the folder on save, so generated `.dart` files are written as a side
effect — the same ones `flxc build` produces. Set it to `false` if you would
rather the editor never wrote anything; syntax diagnostics are unaffected.

## How type errors get back to the .flx

Dart reports errors in generated code, at line numbers that correspond to
nothing you wrote. flxc maps them back by occurrence: code generation emits
user identifiers in source order and never reorders them, so the *n*th `foo`
in the `.dart` is the *n*th `foo` in the `.flx`.

That is a heuristic and is treated as one. When an identifier appears exactly
once, the match is certain. When counts differ — a composable name becomes both
a class and a constructor, for instance — the diagnostic says *located by name*
and includes the generated position. When nothing matches, it reports the
generated location rather than guessing.

The same machinery is available in the terminal:

```bash
flxc analyze apps/ledger/lib/pages
```

## Not done

- No rename, no code actions, no formatting.
- No signature help while typing arguments.
- Jumping into Dart resolves **names, not members**: `useState` and
  `LedgerViewModel` land where they are declared, `vm.setSearch` does not —
  the index holds top-level declarations, so a hit on a member name would be a
  coincidence pointing at the wrong file.
- That index is built when the server starts. Add a hook to flx_runtime and
  the editor finds it after **flx: Restart Language Server**.
- Completion inside `${...}` offers local bindings but not their members —
  that would need Dart type information the server does not have.
- The extension is not packaged or published; it is symlinked from the repo.
