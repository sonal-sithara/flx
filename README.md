# flx

A Compose/Next.js-style DSL for Flutter. You write `.flx`; `flxc` transpiles it
to ordinary Dart. Built on stock Flutter — the SDK is never forked, and the
runtime takes **zero pub dependencies**.

**flx exists to make Flutter read cleanly, the way Jetpack Compose does — and
to do nothing else.** It is not a subset of Flutter and not a walled garden:
anything you can write in Flutter you can write in flx, with any package.
`apps/interop` compiles one screen using BLoC, Provider and GetX together to
keep that honest.

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
| `packages/flx_lsp` | The language server — diagnostics, completion, hover   |
| `apps/ledger`      | **Ledger** — the flagship app, an expense tracker      |
| `tools/vscode-flx` | Syntax highlighting for `.flx`                         |

## Getting started

```bash
make setup     # fetch deps for all four packages
make build     # .flx -> .dart, and regenerate routes.g.dart
make run       # build, then launch Ledger
make watch     # rebuild on every save
make test      # 309 tests across compiler, server, runtime and apps
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
flxc analyze [dir]   # build, then report Dart's type errors on the .flx
flxc file.flx -o out.dart
```

### Type errors land on the .flx

flxc checks syntax; Dart is still the type checker. Left alone, that means
every type error points into a generated file you must never edit:

```
error • The method 'setSerch' isn't defined … • lib/pages/transactions.dart:47:14
```

`flxc analyze` maps it back:

```
error: The method 'setSerch' isn't defined for the type 'TransactionsViewModel'.
  --> apps/ledger/lib/pages/transactions.flx:19:10
   |
19 |       vm.setSerch(text)
   |          ^^^^^^^^
```

It works by occurrence: code generation emits user identifiers in source order
and never reorders them, so the *n*th `foo` in the `.dart` is the *n*th `foo`
in the `.flx`. That is a heuristic and says so — a name appearing once is
certain, a mismatch is labelled *located by name*, and anything unmappable
reports the generated location rather than guessing.

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

## Interop

Any Flutter or third-party widget works, whatever shape its API takes:

```
// A trailing block that produces a widget becomes `builder:`
LayoutBuilder { context, box =>
  Text("width ${box.maxWidth}")
}

// Explicitly named, for APIs that call it something else
ValueListenableBuilder(
  valueListenable: notifier,
  builder: { context, value, child =>
    Column(gap: 4) { Text("$value") }
  },
)

// Zero-argument builders are positional, by the same convention
Obx {  =>
  Text("${controller.count}")
}

// A widget tree as an ordinary argument value
Scaffold(
  appBar: AppBar(title: Text("Hi")),
  body: Column(gap: 8) { Text("in an argument") },
)

// Named constructors, type arguments, raw Dart, and spreads
Image.asset("logo.png")
LazyColumn<Todo>(items: todos) { todo in Text(todo.title) }
(isEmpty ? EmptyState(title: "Nothing") : Text("Loaded"))
...extraRows
```

| Architecture | How it fits |
| --- | --- |
| **Clean / layered** | Native — Ledger *is* this |
| **MVVM** | Native — `ViewModel` + `useViewModel` |
| **BLoC** | `useStream(cubit.stream, initialData: cubit.state)`, or `BlocBuilder` directly |
| **Provider** | `Provider.of<T>(useContext())` in a `val`, or `Consumer` directly |
| **GetX** | `Get.find<T>()` in a `val`, `Obx { => ... }` for reactivity |
| **Riverpod** | Providers work through `useStream`; `ConsumerWidget` does not, since `Composable` is its own StatefulWidget |

## Known limits

- **Dependent fetches.** A `val` cannot read an earlier `useFetch`'s resolved
  value, because hooks are positional and the value only exists inside the
  `.when(data:)` closure. `flxc` rejects it at compile time and points you at
  `name$.data`.
- **Expressions are passed through.** Anything that isn't widget-tree structure
  is handed to Dart verbatim — Dart remains the type checker.
- **One root widget per composable**, and `if`/`for` cannot be that root. Wrap
  them, or use `(a ? B() : C())`.
- **Riverpod's `ConsumerWidget`** cannot be a composable's base class.
- **No rename, code actions or formatting** in the language server, and no
  member completion inside `${...}` — that needs Dart type information the
  server does not have.

## The editor

`packages/flx_lsp` is a language server speaking LSP over stdio. Everything it
answers comes from flxc's own lexer, parser and spans, so the editor can never
disagree with the build.

| | |
| --- | --- |
| Syntax diagnostics | Instant, per keystroke — same message, position and hint as the build |
| Type errors | On save, mapped back onto the `.flx` |
| Completion | Hooks, widgets, arguments, enum shorthands, `Icons`, local `val`s, composables |
| Hover | Signatures and docs; the route for a `@page`; the expression behind a `val` |
| Go to definition | Composables across files, `val`s, parameters — including from inside `${...}` |
| Outline & workspace symbols | Composables with their bindings nested |

The interesting constraint: the parser is fatally strict, and a file you are
typing into does not parse. So completion reads the **token stream**, not the
AST, and falls back to a truncated tokenization when even the lexer fails on a
half-typed string. Navigation and the outline use the last *successful* parse
rather than emptying themselves on every keystroke.

Setup is in [tools/vscode-flx](tools/vscode-flx).

## Status

Production-solid for in-house use: 309 tests, a language server, real
diagnostics that land on the line you wrote, watch mode, and
[Ledger](apps/ledger) — a complete expense tracker written entirely in the DSL,
building for web, iOS, Android and macOS.

Not published to pub.dev, and not yet documented for outside contributors.
That is the deliberate scope: the bar is "trustworthy for our own work", not
"usable by strangers".
