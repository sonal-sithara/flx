# flx

A Compose/Next.js-style DSL for Flutter. You write `.flx`; `flxc` transpiles it
to ordinary Dart. Built on stock Flutter — the SDK is never forked, and the
runtime takes **zero pub dependencies**.

```
composable Greeting(name) {
  val count = useState(0)

  Column(padding: 16, gap: 12, main: .center) {
    Text("Hello ${name}", style: .title)
    Text("Taps: ${count.value}")
    Button("Tap me") {
      count.value++
    }
  }
}
```

## Layout

| Path               | What it is                                            |
| ------------------ | ----------------------------------------------------- |
| `packages/flx`     | The runtime — hooks engine, router, DI, widgets        |
| `packages/flxc`    | The compiler — lexer, parser, codegen, CLI, watch mode |
| `apps/ledger`      | **Ledger** — the flagship app, an expense tracker      |
| `tools/vscode-flx` | Syntax highlighting for `.flx`                         |

## Getting started

```bash
make setup     # fetch deps for all three packages
make build     # .flx -> .dart, and regenerate routes.g.dart
make run       # build, then launch Ledger
make watch     # rebuild on every save
make test      # 210 tests across compiler, runtime and app
```

## The compiler

`flxc` is a hand-written lexer → recursive-descent parser → code generator in
pure Dart. It reports errors the way a compiler should:

```
error: composable 'greeting' must start with a capital letter
  --> lib/pages/settings.flx:1:12
  |
1 | composable greeting {
  |            ^^^^^^^^
  = hint: it becomes a Dart class, so name it 'Greeting'
```

```bash
flxc build [dir]     # transpile + generate routes  (default: lib/pages)
flxc watch [dir]     # rebuild on change, ~15ms, survives syntax errors
flxc check [dir]     # transpile without writing — for CI
flxc file.flx -o out.dart
```

Codegen is pinned by golden tests: `packages/flxc/test/fixtures/*.flx` each have
a committed `.dart.golden`. Accept an intentional change with
`UPDATE_GOLDENS=1 dart test`, then read the diff before committing it.

Goldens compare **text**, though — the fixtures reference types that do not
exist and could never compile. Proof that generated Dart actually compiles and
runs comes from Ledger, which is why every codegen path needs a screen that
uses it. `useFetch` lives on the Insights screen for exactly that reason.

## The DSL

**Declarations.** A file holds any number of composables — a screen plus the
components it is built from. `@page("/route")` makes one a screen: it is wrapped
in a `Scaffold` and registered in the generated route table.

**`val`.** All `val`s come before the widget tree. `val x = useFetch(...)` is
special: it generates the `AsyncValue.when` loading/error wrapping, so `x` is
the resolved value everywhere below.

**Blocks.** A trailing `{ }` after `Column`/`Row`/`Stack`/`Wrap` is children;
after any other widget it is a callback body. The rule is keyed off the widget
name, so it never depends on type inference.

**Control flow.** `if` / `else if` / `else` and `for (x in xs)` work inside any
children block and compile to Dart's collection-if and collection-for, so a
branch may contain several widgets.

**Blocks that bind names.** A trailing block can take parameters, and a
builder widget binds each element instead of building them all:

```
SearchField(query) { text ->            // → (text) { ... }
  vm.setSearch(text)
}
LazyColumn(items: vm.rows) { row, i ->  // → itemBuilder: (row, i) => ...
  Text("${i}. ${row.title}")
}
Screen(title: "Inbox") {                // → Screen(title: ..., children: [...])
  ...
}
```

`Screen` and `Panel` take their block as a `children:` argument, which is how
a widget tree reaches a named parameter — ordinary arguments are captured as
expression tokens, not parsed as widgets. A composable whose root is a
`Screen` is not wrapped in a second Scaffold.

**Shorthands.** `style: .title` → `Styles.title`, `main: .center` →
`MainAxisAlignment.center`, and any `*Icon:` argument resolves against `Icons`.

**Modifiers.** `padding:`, `background:`, `center:` and friends are lifted out
of a layout call into a modifier chain. On non-layout widgets only the
modifiers that cannot collide with a real parameter are lifted — an instance
member always beats an extension method in Dart, so lifting `scrollable:` onto
a widget that declares one produces a baffling error far from its cause.

## The runtime

A hooks engine in ~250 lines, same slot-cursor principle as React: hooks must be
called in the same order every build.

`useState` · `useRef` · `useMemoized` · `useEffect` · `useRebuild` ·
`useListenable` · `useTextEditingController` · `useTextField` · `useFocusNode` ·
`useScrollController` · `useFetch` · `useInterval` · `useDebounced` ·
`useTheme` · `useNavigator` · `useMediaQuery` · `useInject` · `useViewModel`

Widgets: `Screen` · `Panel` · `LazyColumn` · `LazyRow` · `LazyGrid` · `Field` ·
`SearchField` · `Picker` · `Segmented` · `DateField` · `Toggle` · `Tile` ·
`Stat` · `Pill` · `Dot` · `ProgressBar` · `EmptyState` · `Section` · `Button` ·
`Avatar`

Effects run **after the frame**, not during build — so `useEffect(() =>
nav.push(...))` works instead of throwing.

### Dependency injection

```dart
final injector = Injector()
  ..singleton<UserRepository>((_) => UserRepository());

runApp(FlxScope(injector: injector, child: const App()));
```

```
val repo = useInject<UserRepository>()
val vm   = useViewModel<TodosViewModel>()
```

Scopes nest and override, which is what lets a widget test swap a repository
for a fake — see how `apps/ledger/test/app_test.dart` replaces `InsightsService`
with a failing one to drive the error branch of `useFetch`.

### Routing

`@page` annotations generate `routes.g.dart`. Wire it into
`MaterialApp.onGenerateRoute` — one entry point serving `pushNamed`, web URLs
and platform deep links.

```
nav.to(SettingsScreen())   // push a screen object
nav.toPath("/user/42")     // push by path through the route table
```

Query params merge into the param map; unknown paths get a built-in 404.

To finish deep linking you still need the platform manifests: an Android
intent-filter plus `/.well-known/assetlinks.json`, and the iOS Associated
Domains capability plus `/.well-known/apple-app-site-association`.

## Known limits

- **Dependent fetches.** A `val` cannot read an earlier `useFetch`'s resolved
  value, because hooks are positional and the value only exists inside the
  `.when(data:)` closure. `flxc` rejects it at compile time and points you at
  `name$.data`.
- **Expressions are passed through.** Anything that isn't widget-tree structure
  is handed to Dart verbatim — Dart remains the type checker. Errors in an
  expression surface as Dart errors in the generated file.
- **One root widget per composable**, and `if`/`for` cannot be that root.
- **No language server yet** — highlighting only, no completion or inline
  errors.

## Status

Production-solid for in-house use: 210 tests, real diagnostics, watch mode, and
[Ledger](apps/ledger) — a complete expense tracker written entirely in the DSL,
building for web, iOS, Android and macOS.

Not published to pub.dev, and not yet documented for outside contributors.
That is the deliberate scope: the bar is "trustworthy for our own work", not
"usable by strangers".
