import 'dart:io';

import 'package:flx_lsp/src/documents.dart';
import 'package:flx_lsp/src/semantics.dart';
import 'package:flxc/flxc.dart';
import 'package:test/test.dart';

/// A bridge that returns canned results instead of spawning `dart analyze`.
///
/// The real bridge's parsing and mapping are covered by flxc's
/// sourcemap_test; what matters here is the surrounding behaviour — building
/// before analysing, grouping by file, and clearing results that are no
/// longer true.
class FakeBridge implements DartAnalysisBridge {
  FakeBridge(this.results);

  List<MappedDiagnostic> results;
  int calls = 0;
  String? lastDirectory;

  @override
  String get dartExecutable => 'fake';

  @override
  Future<List<MappedDiagnostic>> analyze(
    String directory, {
    String? workingDirectory,
  }) async {
    calls++;
    lastDirectory = directory;
    return results;
  }

  @override
  List<MappedDiagnostic> parseMachineOutput(String output) => results;
}

MappedDiagnostic diagnosticFor(
  String flxPath,
  String text, {
  String severity = 'ERROR',
  MapConfidence confidence = MapConfidence.exact,
}) {
  final source = Source(flxPath, text);
  return MappedDiagnostic(
    severity: severity,
    code: 'UNDEFINED_METHOD',
    message: "The method 'setSerch' isn't defined.",
    generatedPath: flxPath.replaceAll('.flx', '.dart'),
    generatedLine: 47,
    generatedColumn: 14,
    flxPath: flxPath,
    span: Span(source, text.indexOf('Text'), text.indexOf('Text') + 4),
    confidence: confidence,
  );
}

void main() {
  late Directory temp;
  late String flxPath;
  const flx = 'composable A {\n  Text("hi")\n}\n';

  setUp(() {
    temp = Directory.systemTemp.createTempSync('flx_lsp_semantics');
    flxPath = '${temp.path}/a.flx';
    File(flxPath).writeAsStringSync(flx);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('transpiles before analysing', () async {
    final bridge = FakeBridge([]);
    final semantics = SemanticDiagnostics(
      bridge: bridge,
      publish: (_, __) {},
      onLog: (_) {},
    );

    await semantics.refresh(flxPath);

    expect(bridge.calls, 1);
    expect(
      File('${temp.path}/a.dart').existsSync(),
      isTrue,
      reason: 'the analyzer must see generated code that matches the source',
    );
  });

  test('publishes mapped diagnostics against the .flx', () async {
    final published = <String, List<MappedDiagnostic>>{};
    final semantics = SemanticDiagnostics(
      bridge: FakeBridge([diagnosticFor(flxPath, flx)]),
      publish: (path, diagnostics) => published[path] = diagnostics,
      onLog: (_) {},
    );

    await semantics.refresh(flxPath);

    expect(published[flxPath], hasLength(1));
    expect(published[flxPath]!.single.message, contains('setSerch'));
  });

  test('republishes clean files so fixed errors disappear', () async {
    final published = <String, List<MappedDiagnostic>>{};
    final semantics = SemanticDiagnostics(
      bridge: FakeBridge([]),
      publish: (path, diagnostics) => published[path] = diagnostics,
      onLog: (_) {},
    );

    await semantics.refresh(flxPath);

    // Present but empty — a file omitted entirely would keep its stale
    // squiggles in the editor forever.
    expect(published.containsKey(flxPath), isTrue);
    expect(published[flxPath], isEmpty);
  });

  test('skips analysis when the file does not parse', () async {
    File(flxPath).writeAsStringSync('composable lower {\n  Text("x")\n}\n');
    final bridge = FakeBridge([]);
    final semantics = SemanticDiagnostics(
      bridge: bridge,
      publish: (_, __) {},
      onLog: (_) {},
    );

    await semantics.refresh(flxPath);

    // The syntax error is already reported by the fast path, and there is
    // nothing meaningful to type-check until it is fixed.
    expect(bridge.calls, 0);
  });

  test('can be turned off', () async {
    final bridge = FakeBridge([]);
    final semantics = SemanticDiagnostics(
      bridge: bridge,
      enabled: false,
      publish: (_, __) {},
      onLog: (_) {},
    );

    await semantics.refresh(flxPath);
    expect(bridge.calls, 0);
  });

  test('a missing file is ignored rather than throwing', () async {
    final bridge = FakeBridge([]);
    final semantics = SemanticDiagnostics(
      bridge: bridge,
      publish: (_, __) {},
      onLog: (_) {},
    );

    await semantics.refresh('${temp.path}/absent.flx');
    expect(bridge.calls, 0);
  });

  group('LSP conversion', () {
    TextDocument documentFor(String text) =>
        TextDocument(uri: pathToUri(flxPath), text: text, version: 1);

    test('maps severity and carries the code', () {
      final lsp = lspDiagnosticFor(
        documentFor(flx),
        diagnosticFor(flxPath, flx),
      );

      expect(lsp['severity'], 1);
      expect(lsp['source'], 'dart');
      expect(lsp['code'], 'UNDEFINED_METHOD');
      expect(lsp['message'], contains('setSerch'));
    });

    test('warnings and infos map to their own levels', () {
      expect(
        lspDiagnosticFor(
          documentFor(flx),
          diagnosticFor(flxPath, flx, severity: 'WARNING'),
        )['severity'],
        2,
      );
      expect(
        lspDiagnosticFor(
          documentFor(flx),
          diagnosticFor(flxPath, flx, severity: 'INFO'),
        )['severity'],
        3,
      );
    });

    test('a name-located result says so', () {
      final lsp = lspDiagnosticFor(
        documentFor(flx),
        diagnosticFor(flxPath, flx, confidence: MapConfidence.unique),
      );

      // The mapping is a heuristic, and the message admits it rather than
      // pretending to precision it does not have.
      expect(lsp['message'], contains('located by name'));
      expect(lsp['message'], contains('47:14'));
    });

    test('the range points at the mapped span', () {
      final lsp = lspDiagnosticFor(
        documentFor(flx),
        diagnosticFor(flxPath, flx),
      );

      final start = (lsp['range']! as Map)['start']! as Map;
      expect(start['line'], 1, reason: 'the Text("hi") line');
      expect(start['character'], 2);
    });
  });
}
