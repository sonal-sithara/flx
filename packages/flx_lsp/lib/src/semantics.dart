import 'dart:async';
import 'dart:io';

import 'package:flx_compiler/flx_compiler.dart';

import 'documents.dart';

/// Runs the Dart analyzer over generated code and reports its findings on the
/// `.flx` sources.
///
/// flxc only checks syntax. Everything else — unknown methods, wrong types,
/// bad argument names — is Dart's job, and without this the editor would send
/// the author to a generated file they must never edit.
///
/// This runs on **save**, not on every keystroke: spawning the analyzer costs
/// seconds, and syntax diagnostics already cover the fast feedback loop.
class SemanticDiagnostics {
  SemanticDiagnostics({
    required this.publish,
    required this.onLog,
    Compiler? compiler,
    DartAnalysisBridge? bridge,
    this.enabled = true,
  })  : _compiler = compiler ?? Compiler(),
        _bridge = bridge ?? DartAnalysisBridge();

  /// Called with a `.flx` path and the diagnostics now attributed to it.
  final void Function(String flxPath, List<MappedDiagnostic> diagnostics)
      publish;

  final void Function(String message) onLog;
  final bool enabled;

  final Compiler _compiler;
  final DartAnalysisBridge _bridge;

  /// One run at a time per directory, with at most one more queued — a burst
  /// of saves should not spawn a queue of analyzer processes.
  final _running = <String>{};
  final _pending = <String>{};

  /// Transpiles the directory containing [path], then analyzes it.
  Future<void> refresh(String path) async {
    if (!enabled) return;
    final directory = _directoryOf(path);
    if (directory == null) return;

    if (_running.contains(directory)) {
      _pending.add(directory);
      return;
    }
    _running.add(directory);
    try {
      await _run(directory);
    } finally {
      _running.remove(directory);
      if (_pending.remove(directory)) unawaited(refresh(path));
    }
  }

  Future<void> _run(String directory) async {
    // Generated Dart has to exist and match the sources before the analyzer
    // sees it, so the build happens here rather than being assumed.
    try {
      _compiler.build(directory);
    } on FlxError {
      // A syntax error is already reported by the fast path; there is nothing
      // meaningful to analyze until it is fixed.
      return;
    } on FileSystemException catch (error) {
      onLog('flx: could not build $directory: ${error.message}');
      return;
    }

    final List<MappedDiagnostic> diagnostics;
    try {
      diagnostics = await _bridge.analyze(
        directory,
        workingDirectory: _packageRootOf(directory),
      );
    } on ProcessException catch (error) {
      onLog('flx: dart analyze failed: ${error.message}');
      return;
    }

    // Every .flx in the directory is republished, including the ones that are
    // now clean — otherwise a fixed error would linger in the editor.
    final byFile = <String, List<MappedDiagnostic>>{
      for (final path in _flxFilesIn(directory)) path: <MappedDiagnostic>[],
    };
    for (final diagnostic in diagnostics) {
      final path = diagnostic.flxPath;
      if (path == null || !diagnostic.isMapped) continue;
      (byFile[path] ??= []).add(diagnostic);
    }

    byFile.forEach(publish);
  }

  List<String> _flxFilesIn(String directory) {
    final root = Directory(directory);
    if (!root.existsSync()) return const [];
    return [
      for (final entity in root.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.flx')) entity.path,
    ];
  }

  static String? _directoryOf(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.parent.path;
  }

  static String? _packageRootOf(String directory) {
    var current = Directory(directory).absolute;
    for (var depth = 0; depth < 12; depth++) {
      if (File('${current.path}/pubspec.yaml').existsSync()) {
        return current.path;
      }
      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }
    return null;
  }
}

/// Converts a mapped Dart diagnostic into an LSP one.
Map<String, Object?> lspDiagnosticFor(
  TextDocument document,
  MappedDiagnostic diagnostic,
) {
  final span = diagnostic.span!;
  final message = diagnostic.confidence == MapConfidence.unique
      ? '${diagnostic.message}\n\n'
          '(located by name; generated at ${diagnostic.generatedLine}:'
          '${diagnostic.generatedColumn})'
      : diagnostic.message;

  return {
    'range': document.rangeOfSpan(span),
    'severity': switch (diagnostic.severity) {
      'ERROR' => 1,
      'WARNING' => 2,
      _ => 3,
    },
    'source': 'dart',
    'code': diagnostic.code,
    'message': message,
  };
}
