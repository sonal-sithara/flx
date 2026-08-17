import 'dart:io';

import 'source.dart';
import 'sourcemap.dart';

/// One problem the Dart analyzer found in generated code, moved back onto the
/// `.flx` that produced it.
class MappedDiagnostic {
  MappedDiagnostic({
    required this.severity,
    required this.code,
    required this.message,
    required this.generatedPath,
    required this.generatedLine,
    required this.generatedColumn,
    required this.flxPath,
    required this.span,
    required this.confidence,
  });

  /// `ERROR`, `WARNING` or `INFO`.
  final String severity;
  final String code;
  final String message;

  final String generatedPath;
  final int generatedLine;
  final int generatedColumn;

  /// The `.flx` this came from, when one could be identified.
  final String? flxPath;
  final Span? span;
  final MapConfidence confidence;

  bool get isMapped => span != null;
  bool get isError => severity == 'ERROR';

  /// `file:line:col`, preferring the `.flx` location.
  String get location => span != null
      ? span!.location
      : '$generatedPath:$generatedLine:$generatedColumn';

  String render() {
    final label = severity.toLowerCase();
    final buffer = StringBuffer('$label: $message')
      ..write('\n  --> $location');
    if (span != null) {
      buffer
        ..write('\n')
        ..write(span!.render());
      if (confidence == MapConfidence.unique) {
        buffer.write('\n  = note: located by name; the generated code is at '
            '$generatedPath:$generatedLine:$generatedColumn');
      }
    } else {
      buffer.write('\n  = note: this is generated code — the cause is in the '
          '.flx it came from');
    }
    return buffer.toString();
  }
}

/// Runs the Dart analyzer over generated code and reports the results against
/// the `.flx` sources instead.
///
/// flxc checks syntax; Dart remains the type checker. Without this step every
/// type error lands in a file the author must never edit, at a line number
/// that does not correspond to anything they wrote.
class DartAnalysisBridge {
  DartAnalysisBridge({this.dartExecutable = 'dart'});

  final String dartExecutable;

  /// Analyzes [directory] and maps each result back to its `.flx`.
  ///
  /// [workingDirectory] should be the package root so the analyzer picks up
  /// its `analysis_options.yaml` and resolved dependencies.
  Future<List<MappedDiagnostic>> analyze(
    String directory, {
    String? workingDirectory,
  }) async {
    // The analyzer runs in the package root so it picks up the right
    // analysis_options.yaml and resolved dependencies, so the target has to
    // be absolute — it is not relative to that root.
    final target = Directory(directory).absolute.path;

    final result = await Process.run(
      dartExecutable,
      ['analyze', '--format=machine', target],
      workingDirectory: workingDirectory,
    );

    // `dart analyze` exits non-zero when it finds problems, which is not a
    // failure of this bridge. Only an empty stdout with a non-zero exit means
    // the analyzer itself could not run.
    final stdoutText = '${result.stdout}';
    if (stdoutText.trim().isEmpty && result.exitCode > 3) {
      throw ProcessException(
        dartExecutable,
        ['analyze', directory],
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }

    return parseMachineOutput(stdoutText);
  }

  /// Parses `SEVERITY|TYPE|CODE|FILE|LINE|COL|LENGTH|MESSAGE` lines.
  List<MappedDiagnostic> parseMachineOutput(String output) {
    final diagnostics = <MappedDiagnostic>[];
    final mappers = <String, SourceMapper?>{};

    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final parts = trimmed.split('|');
      if (parts.length < 8) continue;

      final severity = parts[0];
      final code = parts[2];
      final path = parts[3];
      final row = int.tryParse(parts[4]);
      final column = int.tryParse(parts[5]);
      if (row == null || column == null) continue;

      // Everything after the seventh field is the message, which may itself
      // contain a pipe.
      final message = _unescape(parts.sublist(7).join('|'));

      final mapper = mappers.putIfAbsent(path, () => _mapperFor(path));
      final mapped = mapper?.mapLineColumn(row, column) ??
          const MappedLocation.unmapped();

      diagnostics.add(MappedDiagnostic(
        severity: severity,
        code: code,
        message: message,
        generatedPath: path,
        generatedLine: row,
        generatedColumn: column,
        flxPath: mapper?.flx.path,
        span: mapped.span,
        confidence: mapped.confidence,
      ));
    }
    return diagnostics;
  }

  /// Pairs a generated `.dart` with the `.flx` beside it.
  SourceMapper? _mapperFor(String dartPath) {
    if (!dartPath.endsWith('.dart') || dartPath.endsWith('.g.dart')) {
      return null;
    }
    final flxPath = dartPath.replaceAll(RegExp(r'\.dart$'), '.flx');
    final flxFile = File(flxPath);
    final dartFile = File(dartPath);
    if (!flxFile.existsSync() || !dartFile.existsSync()) return null;

    return SourceMapper(
      Source(flxPath, flxFile.readAsStringSync()),
      Source(dartPath, dartFile.readAsStringSync()),
    );
  }

  /// The machine format escapes backslashes and pipes in the message.
  static String _unescape(String message) =>
      message.replaceAll(r'\|', '|').replaceAll(r'\\', r'\');
}
