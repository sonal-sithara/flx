import 'dart:io';

import 'package:flx_compiler/flx_compiler.dart';
import 'package:test/test.dart';

/// Golden tests: every `test/fixtures/*.flx` is transpiled and compared to
/// the `.dart.golden` beside it.
///
/// To accept intentional codegen changes:
///   UPDATE_GOLDENS=1 dart test
/// then read the diff before committing it — that diff is the whole point.
void main() {
  final updating = Platform.environment['UPDATE_GOLDENS'] == '1';
  final compiler = Compiler();
  final dir = Directory('test/fixtures');

  final fixtures = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.flx'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('fixtures exist', () {
    expect(fixtures, isNotEmpty,
        reason: 'no .flx fixtures found in ${dir.path}');
  });

  for (final fixture in fixtures) {
    final name = fixture.uri.pathSegments.last;
    final goldenPath = fixture.path.replaceAll('.flx', '.dart.golden');

    test('$name matches its golden', () {
      final source = Source(name, fixture.readAsStringSync());
      final actual = compiler.compileSource(source);
      final golden = File(goldenPath);

      if (updating) {
        golden.writeAsStringSync(actual);
        return;
      }

      expect(
        golden.existsSync(),
        isTrue,
        reason: 'missing golden $goldenPath — run UPDATE_GOLDENS=1 dart test',
      );
      expect(actual, golden.readAsStringSync());
    });
  }
}
