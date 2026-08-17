# flx — Flutter DSL framework

A Compose/Next.js-style framework on top of stock Flutter (never fork the SDK).
Users write `.flx` files; `tools/flxc.js` transpiles them to Dart.

## Architecture
- `tools/flxc.js` — transpiler (tokenizer → parser → codegen). Node.js prototype; goal: port to Dart CLI.
- `lib/clean_ui/` — runtime: own hooks engine (core.dart, NO flutter_hooks dependency),
  context hooks, fluent modifiers, layout extensions, router, styles.
- `lib/pages/*.flx` — source of truth. Generated `.dart` files are never hand-edited.
- `lib/data/` — plain Dart repositories/services (enterprise structure; DSL is UI-only).

## Build
node tools/flxc.js build lib/pages   # transpiles all .flx + generates routes.g.dart
flutter run

## Key invariants
- Zero pub dependencies in the runtime.
- val x = useFetch(...) must auto-generate AsyncValue.when loading/error wrapping.
- @page composables auto-wrap in Scaffold and register in routes.g.dart.
- Context hooks (useNavigator etc.) are build-time only; captured in vals, used in callbacks.

## Next tasks (priority order)
1. (DONE) if/for control flow inside .flx widget trees
2. flxc watch mode (auto-transpile on save)
3. Port flxc to Dart, publish as pub package + CLI
4. VS Code extension: .flx syntax highlighting, then LSP
5. useInject<T>() DI hook + ViewModel pattern
6. Tests: transpiler golden tests + widget tests for the hooks engine
