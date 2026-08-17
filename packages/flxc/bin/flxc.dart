import 'dart:io';

import 'package:flxc/flxc.dart';

const _usage = '''
flxc — the flx compiler

Usage:
  flxc build [dir]            Transpile every .flx under dir and write
                              routes.g.dart  (default dir: lib/pages)
  flxc watch [dir]            Same as build, then rebuild on every change
  flxc check [dir]            Transpile without writing — for CI
  flxc analyze [dir]          Transpile, then run the Dart analyzer and
                              report its findings against the .flx sources
  flxc <file.flx> [-o out]    Transpile a single file

Options:
  --runtime <import>          Import used for the flx runtime
                              (default: package:flx_runtime/flx_runtime.dart)
  -h, --help                  Show this help
''';

Future<void> main(List<String> argv) async {
  final args = List<String>.from(argv);

  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    stdout.write(_usage);
    return;
  }

  var runtimeImport = 'package:flx_runtime/flx_runtime.dart';
  final runtimeIndex = args.indexOf('--runtime');
  if (runtimeIndex >= 0) {
    if (runtimeIndex + 1 >= args.length) {
      _fail('--runtime needs a value, e.g. --runtime package:flx_runtime/flx_runtime.dart');
    }
    runtimeImport = args[runtimeIndex + 1];
    args.removeRange(runtimeIndex, runtimeIndex + 2);
  }

  final compiler = Compiler(runtimeImport: runtimeImport);
  final command = args.first;

  try {
    switch (command) {
      case 'build':
        _report(compiler.build(_dirArg(args), write: true));
      case 'check':
        _report(compiler.build(_dirArg(args), write: false), checked: true);
      case 'watch':
        await Watcher(_dirArg(args), compiler).run();
      case 'analyze':
        await _analyze(compiler, _dirArg(args));
      default:
        if (!command.endsWith('.flx')) {
          _fail("unknown command '$command'\n\n$_usage");
        }
        _compileOne(compiler, command, args);
    }
  } on FlxError catch (e) {
    stderr.writeln(e.render());
    exitCode = 1;
  } on FileSystemException catch (e) {
    stderr.writeln('flxc: ${e.message}${e.path == null ? '' : ' (${e.path})'}');
    exitCode = 1;
  }
}

String _dirArg(List<String> args) =>
    args.length > 1 ? args[1] : 'lib/pages';

void _compileOne(Compiler compiler, String input, List<String> args) {
  final oIndex = args.indexOf('-o');
  final output = oIndex >= 0 && oIndex + 1 < args.length
      ? args[oIndex + 1]
      : input.replaceAll(RegExp(r'\.flx$'), '.dart');

  final source = Source(input, File(input).readAsStringSync());
  File(output).writeAsStringSync(compiler.compileSource(source));
  stdout.writeln('flxc: $input -> $output');
}

/// Transpiles, then reports Dart's own findings at .flx locations.
///
/// flxc checks syntax; Dart is still the type checker. Without this the author
/// is sent to a generated file they must never edit.
Future<void> _analyze(Compiler compiler, String dir) async {
  compiler.build(dir);

  final diagnostics = await DartAnalysisBridge()
      .analyze(dir, workingDirectory: _packageRootOf(dir));

  if (diagnostics.isEmpty) {
    stdout.writeln('flxc: no issues found');
    return;
  }

  var errors = 0;
  var unmapped = 0;
  for (final diagnostic in diagnostics) {
    stderr.writeln(diagnostic.render());
    stderr.writeln();
    if (diagnostic.isError) errors++;
    if (!diagnostic.isMapped) unmapped++;
  }

  final trailer =
      unmapped == 0 ? '' : ', $unmapped could not be traced to a .flx';
  stdout.writeln(
    'flxc: ${diagnostics.length} issue(s), $errors error(s)$trailer',
  );
  if (errors > 0) exitCode = 1;
}

/// Nearest ancestor directory holding a pubspec.yaml, so the analyzer runs
/// with the package's options and resolved dependencies.
String? _packageRootOf(String dir) {
  var current = Directory(dir).absolute;
  for (var depth = 0; depth < 12; depth++) {
    if (File('${current.path}/pubspec.yaml').existsSync()) return current.path;
    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  return null;
}

void _report(BuildResult result, {bool checked = false}) {
  for (final f in result.files) {
    stdout.writeln('flxc: ${f.input} -> ${f.output}');
  }
  final verb = checked ? 'checked' : 'generated';
  stdout.writeln(
    'flxc: $verb ${result.routesPath} '
    '(${result.pageCount} route(s), ${result.composableCount} composable(s))',
  );
}

Never _fail(String message) {
  stderr.writeln('flxc: $message');
  exit(1);
}
