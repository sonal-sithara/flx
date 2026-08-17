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
- `apps/ledger/` — **Ledger**, the flagship app (expense tracker). `domain/` is
  plain Dart, `data/` holds storage + repository + ViewModels, `pages/*.flx`
  are the screens.
- `packages/flx_lsp/` — the language server. `analysis.dart` caches parses,
  `completion.dart` is token-based (never AST-based), `catalog.dart` is the
  hand-written knowledge of hooks and widgets, `semantics.dart` bridges to the
  Dart analyzer.
- `tools/vscode-flx/` — TextMate grammar plus the VS Code client.

`lib/pages/*.flx` is the source of truth; generated `.dart` files are never
hand-edited.

## Build

```bash
make build      # transpile all .flx + generate routes.g.dart
make watch      # rebuild Ledger's pages on save
make test       # 296 tests: compiler goldens, server, runtime, app
make ci         # analyze + build + stale-codegen check + test
make run        # launch Ledger
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
- A trailing `{ }` is children after a layout widget (Column/Row/Stack/Wrap) or
  a container widget (Screen/Panel); an item binding after a builder widget
  (LazyColumn/LazyRow/LazyGrid, `{ x in ... }`); otherwise a callback, which
  may take parameters (`{ v -> ... }`). Always keyed off the widget name,
  never type inference.
- Modifier lifting (`padding:`, `expanded:`, ...) is unrestricted only on
  layout widgets. Everywhere else just `_universalModifiers` are lifted: an
  instance member beats an extension method in Dart, so lifting a name the
  widget actually declares fails far from its cause. Adding a modifier means
  checking that name against flx's own widget parameters.
- Route tables are ordered by specificity, so `/a/new` beats `/a/:id`.
- Generated `.dart` is committed and must be regenerated when its `.flx`
  changes — `make ci` fails on a stale tree.

## Working on the language server

Two rules, both learned the hard way:

- **Completion must never depend on a parse.** The parser throws on the first
  error and a file being typed into is broken by definition — `Column { <here> }`
  has an empty block, which is a syntax error. Completion reads tokens, and
  `tokenizeTolerant` re-lexes the prefix when even the lexer fails (an
  unterminated string is the most common state of all).
- **The catalog is hand-written and will rot.** `catalog_drift_test.dart` reads
  packages/flx and fails when a public widget or hook is undocumented. If you
  add one to the runtime, document it — or add it to `notWidgets` deliberately.

`shorthandValues` in the catalog must agree with `_shorthandTypes` in flxc's
codegen, or the editor offers a completion the compiler then rejects; there is
a test for that too.

## Working on the compiler

Goldens compare generated text only — the fixtures reference undefined types
and could never compile. Ledger is the only proof that generated Dart compiles
and runs, so **every codegen path needs a screen that exercises it**. If you
add one, add the screen too, or it is verified by string comparison alone.
(`useFetch` lives on the Insights screen for this reason; the auto-`Scaffold`
wrap is covered by the transaction form's two route composables.)

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
7. (DONE) Flagship app — `apps/ledger`, an expense tracker
8. (DONE) LSP for `.flx` — diagnostics, completion, hover, definition,
   symbols, plus Dart type errors mapped back onto the `.flx`
9. Ledger backend: the repository layer is already the seam. Sync, auth and
   multi-device would go behind `Storage`/`LedgerRepository`.
10. Publish `flx` + `flxc` to pub.dev (needs docs for outside contributors,
    semver policy, CI).

## Growing the framework

New DSL features have come from the flagship app hitting a wall, not from
speculation. The loop that works: write the screen in `.flx` as it should
read, let flxc fail, then decide whether the gap belongs in the compiler
(syntax), the runtime (a widget or hook), or neither. Record the decision in
a golden fixture or a runtime test before moving on.

## Deliberately not done

- No pub.dev release, no public contributor docs — the chosen bar is
  "production-solid for in-house use", not "strangers can use it".
- No rename, code actions, formatting or signature help in the LSP.
- No member completion inside `${...}` — needs Dart type information.
- No CI automation and no git remote; `make ci` is run by hand.
- Dependent `useFetch` chains are a compile error by design; see README.
