# flx — VS Code support

Syntax highlighting, bracket matching and comment toggling for `.flx` files.

## Install locally

Symlink it into your VS Code extensions folder and reload the window:

```bash
ln -s "$PWD/tools/vscode-flx" ~/.vscode/extensions/flx
```

Open any `.flx` file — the status bar should read **flx**.

## What it highlights

| Element                                | Scope                          |
| -------------------------------------- | ------------------------------ |
| `composable Name`, `val x`, `import`   | declarations                   |
| `@page("/route")`                       | annotation                     |
| `if` / `else` / `for` / `in`            | control flow                   |
| `useState`, `useFetch`, `use*`          | hooks                          |
| `Column` / `Row` / `Stack` / `Wrap`     | layout widgets (children block)|
| Any other `Capitalised` identifier      | widget                         |
| `style: .title`                         | enum shorthand                 |
| `"text ${expr}"`                        | strings with interpolation     |

## Not included yet

A language server — so no go-to-definition, completion or inline errors.
Compile errors still surface with precise `file:line:col` from `flxc watch`,
which VS Code's terminal linkifies. An LSP is the natural next step.
