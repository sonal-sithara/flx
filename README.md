# flx — v6: control flow in widget trees

`.flx` DSL → `flxc` transpiler → Dart. Own hooks engine, own router, zero pub dependencies.

## The full pipeline

```bash
node tools/flxc.js build lib/pages
# → transpiles every .flx
# → generates lib/pages/routes.g.dart from @page annotations
flutter run
```

## Routing

```
@page("/user/:id")
composable UserScreen(id) {
  ...
  Text("User id: ${id}")
}
```

flxc generates the class with an `id` field AND registers it:

```dart
final appRoutes = <RouteDef>[
  RouteDef('/profile',  (params) => const ProfileScreen()),
  RouteDef('/settings', (params) => const SettingsScreen()),
  RouteDef('/user/:id', (params) => UserScreen(id: params['id'] ?? '')),
];
```

Navigate two ways:
- `nav.to(SettingsScreen())` — push a screen object
- `nav.toPath("/user/42")` — push by URL through the route table

Query params work too: `/user/42?tab=posts` → `params['tab']`.
Unknown paths get a built-in 404 screen.

## Deep links
`main.dart` wires the table into `MaterialApp.onGenerateRoute` — the single entry
point for pushNamed, web URLs, AND platform deep links. To finish deep linking:

- **Android**: add an intent-filter for your domain in AndroidManifest.xml,
  host `/.well-known/assetlinks.json` on your site
- **iOS**: add Associated Domains capability, host
  `/.well-known/apple-app-site-association`

Then `https://yourapp.com/user/42` opens the app directly on UserScreen(id: '42') —
the route table does the matching, no extra code.

## Demo flow
Profile (`/profile`) → "Settings" (object push) → back → "Open user 42" (path push
through the router, proving deep-link matching works).

## Honest status — what's NOT done yet
- (DONE in v6: if/else + for in widget trees → Dart collection-if/for)
- watch mode, IDE support (highlighting/LSP), Dart port of flxc
- DI (`useInject<T>()`), transpiler test suite
See CLAUDE.md for the prioritized task list — the repo is set up for Claude Code.

## New in v6: control flow

```
if (showTip.value) {
  Text("Visible", style: .caption)
} else {
  Text("Hidden", style: .caption)
}
for (todo in todos.value) {
  Text("• ${todo}")
}
```

Generates Dart collection-if / collection-for (with spreads), so multiple
children per branch work. `else if` chains are supported.

DSL rule update: trailing { } after Column/Row/Stack/Wrap = children
(widgets, if, for). After any other widget = callback. This is now
deterministic by widget name.
