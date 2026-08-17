import 'package:test/test.dart';

import 'harness.dart';

/// Completion is the feature that has to work on broken input, because a file
/// being typed into is broken by definition. These tests deliberately use
/// unparseable snippets.
void main() {
  late TestClient client;

  setUp(() async => client = await startedClient());
  tearDown(() async => client.close());

  group('context detection', () {
    test('top level offers declarations, not widgets', () async {
      final labels = await completionLabels(client, '|');

      expect(labels, containsAll(['composable', 'import', 'page']));
      expect(labels, isNot(contains('Column')));
      expect(labels, isNot(contains('useState')));
    });

    test('a val initialiser offers hooks', () async {
      final labels = await completionLabels(client, '''
composable A {
  val count = |
}
''');

      expect(labels, containsAll(['useState', 'useFetch', 'useViewModel']));
      expect(labels, isNot(contains('Column')),
          reason: 'a widget is not an expression here');
    });

    test('a child position offers widgets and control flow', () async {
      final labels = await completionLabels(client, '''
composable A {
  Column {
    |
  }
}
''');

      expect(labels, containsAll(['Text', 'Column', 'LazyColumn', 'Screen']));
      expect(labels, containsAll(['if', 'for']));
      expect(labels, isNot(contains('useState')),
          reason: 'hooks belong in a val, not the widget tree');
    });

    test('an argument list offers that widget\'s arguments', () async {
      final labels = await completionLabels(client, '''
composable A {
  Tile(|)
}
''');

      expect(labels, containsAll(['title', 'subtitle', 'trailing', 'onTap']));
      expect(labels, contains('expanded'), reason: 'modifiers apply anywhere');
    });

    test('a layout argument list adds the layout arguments', () async {
      final labels = await completionLabels(client, '''
composable A {
  Column(|)
}
''');

      expect(labels, containsAll(['gap', 'main', 'cross']));
      expect(labels, contains('padding'),
          reason: 'padding lifts to a modifier on layouts');
    });

    test('after a comma it is still an argument position', () async {
      final labels = await completionLabels(client, '''
composable A {
  Screen(title: "x", |)
}
''');

      expect(labels, containsAll(['subtitle', 'scrollable', 'fabIcon']));
    });
  });

  group('enum shorthands', () {
    test('style: . offers the Styles members', () async {
      final labels = await completionLabels(client, '''
composable A {
  Text("hi", style: .|)
}
''');

      expect(labels, containsAll(['.title', '.subtitle', '.body', '.caption']));
    });

    test('main: . offers MainAxisAlignment', () async {
      final labels = await completionLabels(client, '''
composable A {
  Column(main: .|) {
    Text("hi")
  }
}
''');

      expect(labels, containsAll(['.center', '.spaceBetween', '.start']));
    });

    test('any *Icon argument offers Icons', () async {
      final labels = await completionLabels(client, '''
composable A {
  Screen(fabIcon: .|) {
    Text("hi")
  }
}
''');

      expect(labels, containsAll(['.add', '.edit', '.search']));
    });

    test('shorthands are offered straight after the colon too', () async {
      final labels = await completionLabels(client, '''
composable A {
  Column(cross:|) {
    Text("hi")
  }
}
''');

      expect(labels, containsAll(['.start', '.stretch']));
    });
  });

  group('works on files that do not parse', () {
    test('an unterminated argument list still completes', () async {
      // The parser dies on this; the token stream does not.
      final labels = await completionLabels(client, '''
composable A {
  Text("hi"
  Column(|
''');

      expect(labels, containsAll(['gap', 'main']));
    });

    test('an unterminated string does not break the file after it', () async {
      // The lexer itself throws here, so this exercises tokenizeTolerant.
      final labels = await completionLabels(client, '''
composable A {
  Column {
    |
    Text("unterminated
  }
}
''');

      expect(labels, contains('Text'));
    });

    test('a half-typed hook name still resolves the context', () async {
      final labels = await completionLabels(client, '''
composable A {
  val x = use|
''');

      expect(labels, contains('useState'));
    });
  });

  group('locals', () {
    test('vals declared above are offered', () async {
      final labels = await completionLabels(client, '''
composable A {
  val repo  = useInject<Repo>()
  val count = useState(0)
  val other = |
}
''');

      expect(labels, containsAll(['repo', 'count']));
    });

    test('composable parameters are offered', () async {
      final labels = await completionLabels(client, '''
composable Detail(id, tab) {
  val thing = |
}
''');

      expect(labels, containsAll(['id', 'tab']));
    });

    test('composables in the file are offered as widgets', () async {
      final labels = await completionLabels(client, '''
composable Badge(label) {
  Text(label)
}

composable A {
  Column {
    |
  }
}
''');

      expect(labels, contains('Badge'));
    });
  });

  group('suppression', () {
    test('nothing is offered inside a string', () async {
      final labels = await completionLabels(client, '''
composable A {
  Text("hello |")
}
''');

      expect(labels, isEmpty);
    });

    test('nothing is offered inside a comment', () async {
      final labels = await completionLabels(client, '''
composable A {
  // a note about | things
  Text("hi")
}
''');

      expect(labels, isEmpty);
    });

    test('but interpolation inside a string does complete', () async {
      final labels = await completionLabels(client, '''
composable A {
  val name = useState("x")
  Text("hello \${|}")
}
''');

      expect(labels, contains('name'),
          reason: r'${...} re-opens code inside a string');
    });
  });

  group('item shape', () {
    test('hooks carry a signature, docs and a snippet', () async {
      final (:text, :offset) = cursor('''
composable A {
  val x = |
}
''');
      await openDocument(client, text);
      final result = await client.request('textDocument/completion', {
        'textDocument': {'uri': testUri},
        'position': positionOf(text, offset),
      }) as Map<String, Object?>;

      final items = result['items']! as List;
      final useState = items.firstWhere(
        (i) => (i as Map)['label'] == 'useState',
      ) as Map<String, Object?>;

      expect(useState['detail'], contains('StateRef<T>'));
      expect(
        (useState['documentation']! as Map)['value'],
        contains('rebuilds the composable'),
      );
      expect(useState['insertTextFormat'], 2, reason: 'snippet format');
      expect(useState['insertText'], contains(r'${1:'));
    });

    test('argument items insert the colon', () async {
      final (:text, :offset) = cursor('''
composable A {
  Tile(|)
}
''');
      await openDocument(client, text);
      final result = await client.request('textDocument/completion', {
        'textDocument': {'uri': testUri},
        'position': positionOf(text, offset),
      }) as Map<String, Object?>;

      final items = result['items']! as List;
      final title =
          items.firstWhere((i) => (i as Map)['label'] == 'title') as Map;

      expect(title['insertText'], 'title: ');
    });
  });
}
