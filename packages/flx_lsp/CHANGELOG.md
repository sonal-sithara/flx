# Changelog

## 0.2.0

- Go-to-definition now reaches the Dart underneath. A new `dart_index.dart`
  scans Dart declarations across the workspace, the runtime and the Flutter
  SDK, so F12 on a hook, widget or ViewModel opens the real source instead of
  stopping at the `.flx` file boundary.
- Requires `flx_compiler` ^0.2.0.

## 0.1.0

First release.

See the [repository README](https://github.com/sonal-sithara/flx) for what the
project is and where it is going. In short: production-solid for in-house use,
not yet battle-tested by strangers. The API is expected to move before 1.0.
