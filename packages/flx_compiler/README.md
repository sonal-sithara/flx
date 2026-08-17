# flxc

The compiler for [flx](https://github.com/sonal-sithara/flx). Transpiles `.flx`
into ordinary Flutter Dart, generates the route table, and reports Dart's own
type errors against the `.flx` that produced them.

## Command line

```bash
dart pub global activate flxc

flxc build [dir]     # transpile + generate routes  (default: lib/pages)
flxc watch [dir]     # rebuild on change, survives syntax errors
flxc check [dir]     # transpile without writing — for CI
flxc analyze [dir]   # build, then report Dart's type errors on the .flx
flxc file.flx -o out.dart
```

## Errors

Diagnostics carry a location, a caret and a fix:

```
error: composable 'greeting' must start with a capital letter
  --> lib/pages/settings.flx:1:12
  |
1 | composable greeting {
  |            ^^^^^^^^
  = hint: it becomes a Dart class, so name it 'Greeting'
```

`flxc analyze` extends that to Dart's own errors, which otherwise land in
generated files at line numbers corresponding to nothing you wrote. It works
by occurrence — code generation emits user identifiers in source order and
never reorders them, so the *n*th `foo` in the `.dart` is the *n*th `foo` in
the `.flx`. That is a heuristic and reports itself as one: a unique name is
certain, a mismatch is labelled _located by name_, and anything unmappable
reports the generated location rather than guessing.

## As a library

```dart
import 'package:flx_compiler/flx_compiler.dart';

final source = Source('screen.flx', text);
final ast    = Parser.parse(source);   // throws FlxError
final dart   = CodeGenerator(ast, runtimeImport: 'package:flx_runtime/flx_runtime.dart')
    .generate();
```

The language server is built entirely on this API, which is the point: the
editor and the build agree because they run the same lexer, parser and spans.

Errors are always `FlxError`, carrying a `Span` that renders with a caret and
a hint. Anything else is a bug.

## License

BSD-3-Clause.
