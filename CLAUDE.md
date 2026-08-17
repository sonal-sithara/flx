# flx — Flutter DSL framework

A Compose/Next.js-style framework on top of stock Flutter (never fork the SDK).
Users write `.flx` files; `flxc` transpiles them to Dart.

## Architecture

Monorepo with path dependencies — no melos, no workspace tooling.

- `packages/flxc/` — the compiler, pure Dart, zero runtime deps.
  `lexer.dart` → `parser.dart` → `codegen.dart`, with `diagnostics.dart` +
  `source.dart` providing `file:line:col` errors with a caret. `watcher.dart`
  is watch mode; `bin/flxc.dart` is the CLI.
- `packages/flx/` — the runtime. Own hooks engine (`core.dart`, NO
  flutter_hooks), context hooks, DI (`di.dart`), fluent modifiers, layout
  extensions, router, styles.
- `example/` — demo Flutter app. `lib/pages/*.flx` is the source of truth;
  generated `.dart` files are never hand-edited.
- `tools/vscode-flx/` — TextMate grammar for `.flx`.

## Build

```bash
make build      # transpile all .flx + generate routes.g.dart
make watch      # rebuild on save
make test       # 85 tests: compiler goldens, runtime widget tests, app e2e
make ci         # analyze + build + stale-codegen check + test
make run        # launch the example app
```

## Key invariants

- Zero pub dependencies in the runtime (`packages/flx`). Flutter and nothing
  else. `flxc` is dev tooling and may take dev-only deps.
- `val x = useFetch(...)` must auto-generate `AsyncValue.when` loading/error
  wrapping, and `x` is the unwrapped data inside the UI.
- `@page` composables auto-wrap in `Scaffold` and register in `routes.g.dart`.
- Context hooks (`useNavigator` etc.) are build-time only; captured in vals,
  used in callbacks.
- Hooks are positional. Effects run **post-frame**, never during build.
- A trailing `{ }` after Column/Row/Stack/Wrap is children; after anything else
  it is a callback. Keyed off the widget name, never type inference.
- Generated `.dart` is committed and must be regenerated when its `.flx`
  changes — `make ci` fails on a stale tree.

## Working on the compiler

Codegen changes must be reflected in goldens:

```bash
cd packages/flxc && UPDATE_GOLDENS=1 dart test   # then READ the diff
```

Error messages are tested like features in `test/error_test.dart` — message,
line, column and hint. New diagnostics get a test there.

## Next tasks (priority order)

1. (DONE) if/for control flow inside .flx widget trees
2. (DONE) flxc watch mode
3. (DONE) Port flxc to Dart
4. (DONE) VS Code `.flx` syntax highlighting
5. (DONE) `useInject<T>()` DI hook + ViewModel pattern
6. (DONE) Transpiler golden tests + widget tests for the hooks engine
7. **Flagship app** — the real product built on flx. Scope not yet decided.
8. LSP for `.flx`: diagnostics on save first, then completion and
   go-to-definition. The parser already carries spans for this.
9. Publish `flx` + `flxc` to pub.dev (needs docs for outside contributors,
   semver policy, CI).

## Deliberately not done

- No pub.dev release, no public contributor docs — the chosen bar is
  "production-solid for in-house use", not "strangers can use it".
- No LSP. Highlighting only.
- Dependent `useFetch` chains are a compile error by design; see README.
