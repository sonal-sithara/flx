import 'dart:io';

import 'package:flx_lsp/src/dart_index.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// The index is the only thing standing between the reader and the half of a
/// `.flx` file that is Dart: `useState`, `Button`, their own ViewModels. It is
/// a scan rather than a parse, so what these tests really pin down is the line
/// between "shapes Dart writes" and "shapes that would resolve to the wrong
/// place".
void main() {
  group('scanning', () {
    late DartIndex index;

    setUp(() => index = DartIndex());

    test('finds top-level declarations of every kind', () {
      index.indexSource('file:///a.dart', '''
class Button extends StatelessWidget {}
abstract class Storage {}
final class Ledger {}
sealed class Event {}
mixin Disposable {}
enum Mode { light, dark }
extension Sugar on String {}
typedef ItemBuilder<T> = Widget Function(T item);
StateRef<T> useState<T>(T initial) {}
void main() {}
''');

      for (final name in [
        'Button',
        'Storage',
        'Ledger',
        'Event',
        'Disposable',
        'Mode',
        'Sugar',
        'ItemBuilder',
        'useState',
        'main',
      ]) {
        expect(index.lookup(name), isNotEmpty, reason: '$name was not indexed');
      }
    });

    test('locates a declaration on its own line and column', () {
      index.indexSource('file:///a.dart', '''
// a comment
class Widget {}

StateRef<T> useState<T>(T initial) {}
''');

      final widget = index.lookup('Widget').single;
      expect(widget.line, 1);
      expect(widget.character, 6, reason: 'past `class `');
      expect(widget.length, 'Widget'.length);

      final hook = index.lookup('useState').single;
      expect(hook.line, 3);
      expect(hook.character, 'StateRef<T> '.length);
    });

    test('ignores members, which are indented', () {
      index.indexSource('file:///a.dart', '''
class Screen {
  Widget build(BuildContext context) {}
  void dispose() {}
}
''');

      expect(index.lookup('build'), isEmpty);
      expect(index.lookup('dispose'), isEmpty);
      expect(index.lookup('Screen'), isNotEmpty);
    });

    test('a constructor call at the start of a line is not a declaration', () {
      // The one that would break everything: `final x = Foo()` indexing Foo,
      // so every jump to Foo lands on a use site.
      index.indexSource('file:///a.dart', '''
final injector = Injector();
const empty = Text("");
''');

      expect(index.lookup('Injector'), isEmpty);
      expect(index.lookup('Text'), isEmpty);
    });

    test('code quoted in a string is not a declaration', () {
      // Found by the VS Code suite, not by reasoning: this very file declares
      // `useState` inside a fixture string, and go-to-definition on the real
      // hook landed here instead of in flx_runtime.
      index.indexSource('file:///a.dart', """
const fixture = '''
class Quoted {}
StateRef<T> useState<T>(T initial) {}
''';

// class Commented {}
/* StateRef<T> useCommented<T>(T initial) {} */
class Real {}
""");

      expect(index.lookup('Quoted'), isEmpty);
      expect(index.lookup('useState'), isEmpty);
      expect(index.lookup('Commented'), isEmpty);
      expect(index.lookup('useCommented'), isEmpty);
      expect(index.lookup('Real'), isNotEmpty, reason: 'the one real one');
    });

    test('blanking a string leaves later declarations on their own lines', () {
      index.indexSource('file:///a.dart', """
const fixture = '''
one
two
''';
class After {}
""");

      expect(index.lookup('After').single.line, 4);
    });

    test('keeps every declaration of a shared name, in index order', () {
      index
        ..indexSource('file:///first.dart', 'class Badge {}\n')
        ..indexSource('file:///second.dart', 'class Badge {}\n');

      final badges = index.lookup('Badge');
      expect(badges, hasLength(2));
      expect(badges.first.uri, 'file:///first.dart');
    });
  });

  group('the real runtime', () {
    test('hooks and widgets resolve to where they are declared', () {
      final runtime = Directory('../flx_runtime/lib');
      expect(runtime.existsSync(), isTrue,
          reason: 'expected packages/flx_runtime beside flx_lsp');

      final index = DartIndex()..addDirectory(runtime.path);

      final useState = index.lookup('useState');
      expect(useState, isNotEmpty, reason: 'the most-used hook of all');
      expect(useState.first.uri, endsWith('core.dart'));

      final button = index.lookup('Button');
      expect(button, isNotEmpty);
      expect(button.first.uri, endsWith('widgets.dart'));
    });
  });

  group('resolvedPackages', () {
    test('finds flx_runtime from an app that only depends on it', () {
      // apps/ledger is its own workspace root in the editor, and flx_runtime
      // lives two directories up. package_config is what bridges that.
      final packages = resolvedPackages('../../apps/ledger');
      expect(packages['flx_runtime'], isNotNull,
          reason: 'run `make setup` if this fails');
      expect(
        Directory(packages['flx_runtime']!).existsSync(),
        isTrue,
        reason: 'resolved to ${packages['flx_runtime']}',
      );
    });
  });

  group('go to definition', () {
    late Directory root;
    late TestClient client;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('flx_lsp_index');
      Directory('${root.path}/lib').createSync(recursive: true);
      File('${root.path}/lib/runtime.dart').writeAsStringSync('''
/// A fake hook, so the test does not depend on the real one.
StateRef<T> useThing<T>(T initial) {}

class Gadget extends StatelessWidget {}
''');
      File('${root.path}/lib/view_model.dart').writeAsStringSync('''
class LedgerViewModel extends ViewModel {
  void setSearch(String text) {}
}
''');

      client = TestClient();
      await client.request('initialize', {
        'rootUri': Uri.file(root.path).toString(),
        'capabilities': <String, Object?>{},
      });
      await client.notify('initialized', {});
    });

    tearDown(() async {
      await client.close();
      root.deleteSync(recursive: true);
    });

    const source = '''
composable Screen {
  val thing = useThing(0)
  val vm = useInject<LedgerViewModel>()

  Column {
    Gadget(label: "x")
    Button("go") {
      vm.setSearch("q");
    }
  }
}
''';

    Future<List> definitionOf(Pattern needle, {int occurrence = 0}) async {
      await openDocument(client, source);
      return await at(
        client,
        'textDocument/definition',
        source,
        needle,
        occurrence: occurrence,
      ) as List;
    }

    test('jumps to a hook in Dart', () async {
      final result = await definitionOf('useThing');
      expect(result, isNotEmpty);
      final location = result.first as Map<String, Object?>;
      expect(location['uri'], endsWith('runtime.dart'));
      expect(((location['range']! as Map)['start']! as Map)['line'], 1);
    });

    test('jumps to a widget class in Dart', () async {
      final result = await definitionOf('Gadget');
      expect(result, isNotEmpty);
      expect((result.first as Map)['uri'], endsWith('runtime.dart'));
    });

    test('jumps to a type named inside an expression', () async {
      final result = await definitionOf('LedgerViewModel');
      expect(result, isNotEmpty);
      expect((result.first as Map)['uri'], endsWith('view_model.dart'));
    });

    test('a member is not resolved to a top-level name', () async {
      // `vm.setSearch` is a method. The index only knows top-level names, so
      // any hit here would be a coincidence pointing somewhere wrong.
      expect(await definitionOf('setSearch'), isEmpty);
    });

    test('an argument label is not a reference', () async {
      expect(await definitionOf('label'), isEmpty);
    });
  });
}
