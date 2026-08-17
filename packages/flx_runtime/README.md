# flx_runtime

The runtime half of [flx](https://github.com/sonal-sithara/flx), a
Compose-style DSL for Flutter. **Zero pub dependencies** — Flutter and nothing
else.

```yaml
dependencies:
  flx_runtime: ^0.1.0
```

```dart
import 'package:flx_runtime/flx_runtime.dart';
```

Named `flx_runtime` because `flx` on pub.dev belongs to an unrelated 2018
package for Flutter's old bundle format. The DSL, the file extension and the
project are all still called flx.

Usable on its own, without the DSL: the hooks, widgets and DI container are
ordinary Dart.

```dart
class Counter extends Composable {
  const Counter({super.key});

  @override
  Widget build(BuildContext context) {
    final count = useState(0);
    return [
      Text('Taps: ${count.value}'),
      Button('Tap me', () => count.value++),
    ].column(gap: 12).padding(16);
  }
}
```

## What's in it

**Hooks** — a slot-cursor engine, same principle as React, in ~250 lines.
Effects run _after the frame_, not during build, so `useEffect(() => nav.push(…))`
works instead of throwing.

`useState` · `useRef` · `useMemoized` · `useEffect` · `useRebuild` ·
`useListenable` · `useTextEditingController` · `useTextField` · `useFocusNode` ·
`useScrollController` · `useFetch` · `useStream` · `useStreamValue` ·
`useInterval` · `useDebounced` · `useTheme` · `useNavigator` · `useMediaQuery` ·
`useInject` · `useViewModel`

**Widgets** — `Screen` · `Panel` · `LazyColumn` · `LazyRow` · `LazyGrid` ·
`Field` · `SearchField` · `Picker` · `Segmented` · `DateField` · `Toggle` ·
`Tile` · `Stat` · `Pill` · `Dot` · `ProgressBar` · `EmptyState` · `Section` ·
`Button` · `Avatar`

**DI** — `Injector`, `FlxScope`, `useInject`, and a `ViewModel` base class.
Scopes nest and override, which is what lets a widget test swap a repository
for a fake.

**Routing** — `RouteDef` and `AppRouter`, wired into
`MaterialApp.onGenerateRoute`: one entry point for `pushNamed`, web URLs and
platform deep links.

## Hook rules

Hooks are positional, so they must run in the same order on every build — no
hooks inside `if`, a loop, or after an early return. Calling fewer than last
time is caught with a readable error rather than silently handing a slot to
the wrong hook.

Context hooks (`useNavigator`, `useTheme`, …) are build-time only: capture
them in a variable during `build`, then use that inside callbacks.

## License

BSD-3-Clause.
