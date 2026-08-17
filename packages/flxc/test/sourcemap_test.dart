import 'package:flxc/src/compiler.dart';
import 'package:flxc/src/dart_analysis.dart';
import 'package:flxc/src/source.dart';
import 'package:flxc/src/sourcemap.dart';
import 'package:test/test.dart';

/// The mapper is a heuristic, so these tests pin down both what it gets right
/// and where it deliberately refuses to guess.
void main() {
  final compiler = Compiler();

  /// Compiles [flx] and returns a mapper over the real generated output.
  SourceMapper mapperFor(String flx) {
    final source = Source('screen.flx', flx);
    final dart = compiler.compileSource(source);
    return SourceMapper(source, Source('screen.dart', dart));
  }

  /// Offset of the [occurrence]th [needle] in [text].
  int offsetOf(String text, String needle, [int occurrence = 0]) {
    var index = -1;
    for (var i = 0; i <= occurrence; i++) {
      index = text.indexOf(needle, index + 1);
      if (index < 0) throw ArgumentError('no occurrence $occurrence');
    }
    return index;
  }

  group('mapping', () {
    test('maps an identifier back to the line that wrote it', () {
      const flx = '''
composable A {
  val vm = useViewModel<Thing>()

  Column(gap: 8) {
    Button("Go") {
      vm.doTheThing()
    }
  }
}
''';
      final mapper = mapperFor(flx);
      final dart = mapper.dart.text;

      final mapped = mapper.map(offsetOf(dart, 'doTheThing'));

      expect(mapped.isMapped, isTrue);
      expect(mapped.span!.line, 6, reason: 'the vm.doTheThing() line');
      expect(flx.split('\n')[mapped.span!.line - 1], contains('doTheThing'));
    });

    test('picks the right occurrence when a name is used repeatedly', () {
      const flx = '''
composable A {
  val vm = useViewModel<Thing>()

  Column(gap: 8) {
    Text(vm.first)
    Text(vm.second)
    Text(vm.third)
  }
}
''';
      final mapper = mapperFor(flx);
      final dart = mapper.dart.text;

      // `vm` appears four times in both files, in the same order.
      final third = mapper.map(offsetOf(dart, 'vm.third'));
      expect(third.confidence, MapConfidence.exact);
      expect(third.span!.line, 7);

      final first = mapper.map(offsetOf(dart, 'vm.first'));
      expect(first.span!.line, 5);
    });

    test('a name appearing once maps even when the counts differ', () {
      const flx = '''
composable Greeting {
  Text("hi", style: .title)
}
''';
      final mapper = mapperFor(flx);
      final dart = mapper.dart.text;

      // `Greeting` appears twice in the Dart — the class and its constructor —
      // but only once in the .flx.
      final mapped = mapper.map(offsetOf(dart, 'Greeting'));
      expect(mapped.confidence, MapConfidence.unique);
      expect(mapped.span!.line, 1);
    });

    test('strips the useFetch \$ suffix', () {
      const flx = '''
composable A {
  val user = useFetch(api.currentUser)

  Text(user.name)
}
''';
      final mapper = mapperFor(flx);
      final dart = mapper.dart.text;

      // The AsyncValue is emitted as `user\$`; the DSL only wrote `user`.
      final mapped = mapper.map(offsetOf(dart, r'user$'));
      expect(mapped.isMapped, isTrue);
      expect(mapped.span!.line, 2);
    });

    test('maps a 1-based line and column, as dart analyze reports them', () {
      const flx = '''
composable A {
  val vm = useViewModel<Thing>()

  Button("Go") {
    vm.misspelled()
  }
}
''';
      final mapper = mapperFor(flx);
      final dart = mapper.dart.text;

      final offset = offsetOf(dart, 'misspelled');
      final line = '\n'.allMatches(dart.substring(0, offset)).length + 1;
      final column = offset - (dart.lastIndexOf('\n', offset - 1) + 1) + 1;

      final mapped = mapper.mapLineColumn(line, column);
      expect(mapped.isMapped, isTrue);
      expect(mapped.span!.line, 5);
    });
  });

  group('refusing to guess', () {
    test('generated-only names do not map', () {
      const flx = '''
composable A {
  Text("hi", style: .title)
}
''';
      final mapper = mapperFor(flx);
      final dart = mapper.dart.text;

      // `Styles` is invented by codegen; the .flx only wrote `.title`.
      final mapped = mapper.map(offsetOf(dart, 'Styles'));
      expect(mapped.isMapped, isFalse);
      expect(mapped.confidence, MapConfidence.none);
    });

    test('an offset in whitespace does not map', () {
      final mapper = mapperFor('composable A {\n  Text("hi")\n}\n');
      expect(mapper.map(0).isMapped, isFalse);
    });

    test('an out-of-range line does not map', () {
      final mapper = mapperFor('composable A {\n  Text("hi")\n}\n');
      expect(mapper.mapLineColumn(9999, 1).isMapped, isFalse);
      expect(mapper.mapLineColumn(0, 1).isMapped, isFalse);
    });

    test('identifiers inside strings are invisible to both sides equally', () {
      const flx = '''
composable A {
  val count = useState(0)

  Text("count is \${count.value}")
}
''';
      final mapper = mapperFor(flx);
      final dart = mapper.dart.text;

      // `count` occurs once outside a string on each side, so the counts
      // agree and the mapping stays exact.
      final mapped = mapper.map(offsetOf(dart, 'count'));
      expect(mapped.isMapped, isTrue);
      expect(mapped.span!.line, 2);
    });
  });

  group('machine output parsing', () {
    final bridge = DartAnalysisBridge();

    test('parses severity, code, location and message', () {
      final diagnostics = bridge.parseMachineOutput(
        'ERROR|COMPILE_TIME_ERROR|UNDEFINED_METHOD|/tmp/x.dart|47|14|8|'
        "The method 'setSerch' isn't defined.",
      );

      expect(diagnostics, hasLength(1));
      final diagnostic = diagnostics.single;
      expect(diagnostic.severity, 'ERROR');
      expect(diagnostic.isError, isTrue);
      expect(diagnostic.code, 'UNDEFINED_METHOD');
      expect(diagnostic.generatedLine, 47);
      expect(diagnostic.generatedColumn, 14);
      expect(diagnostic.message, "The method 'setSerch' isn't defined.");
    });

    test('keeps a message that contains a pipe', () {
      final diagnostics = bridge.parseMachineOutput(
        r'INFO|HINT|X|/tmp/x.dart|1|1|1|Use a || b instead.',
      );
      expect(diagnostics.single.message, 'Use a || b instead.');
    });

    test('ignores blank and malformed lines', () {
      final diagnostics = bridge.parseMachineOutput(
        '\n'
        'not a diagnostic\n'
        'ERROR|A|B|/tmp/x.dart|1|1|1|Real one\n'
        '\n',
      );
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.message, 'Real one');
    });

    test('an unmappable diagnostic still reports the generated location', () {
      final diagnostics = bridge.parseMachineOutput(
        'ERROR|A|B|/nowhere/absent.dart|3|5|2|Something',
      );

      final diagnostic = diagnostics.single;
      expect(diagnostic.isMapped, isFalse);
      expect(diagnostic.location, '/nowhere/absent.dart:3:5');
      expect(diagnostic.render(), contains('generated code'));
    });
  });
}
