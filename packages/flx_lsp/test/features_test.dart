import 'package:test/test.dart';

import 'harness.dart';

const _screen = '''
import "../data/repo.dart"

composable Badge(label) {
  Text(label, style: .caption)
}

@page("/inbox/:id")
composable InboxScreen(id) {
  val repo  = useInject<Repo>()
  val count = useState(0)

  Column(gap: 8) {
    Badge(label: id)
    Text("Seen \${count.value}")
  }
}
''';

Future<Object?> at(
  TestClient client,
  String method,
  String text,
  Pattern needle, {
  int occurrence = 0,
}) async {
  var index = -1;
  for (var i = 0; i <= occurrence; i++) {
    index = text.indexOf(needle, index + 1);
    if (index < 0) throw ArgumentError('no match $occurrence for $needle');
  }
  return client.request(method, {
    'textDocument': {'uri': testUri},
    'position': positionOf(text, index + 1),
  });
}

void main() {
  late TestClient client;

  setUp(() async {
    client = await startedClient();
    await openDocument(client, _screen);
  });
  tearDown(() async => client.close());

  group('diagnostics', () {
    test('a clean file reports none', () async {
      expect(client.diagnosticsFor(testUri), isEmpty);
    });

    test('a syntax error is reported at the right place, with the hint',
        () async {
      await openDocument(client, 'composable lower {\n  Text("hi")\n}\n');
      final diagnostics = client.diagnosticsFor(testUri);

      expect(diagnostics, hasLength(1));
      final diagnostic = diagnostics.single;
      expect(diagnostic['message'], contains('must start with a capital'));
      expect(diagnostic['message'], contains("name it 'Lower'"),
          reason: 'the hint is part of the message');
      expect(diagnostic['severity'], 1);
      expect(diagnostic['source'], 'flxc');

      final range = diagnostic['range']! as Map<String, Object?>;
      final start = range['start']! as Map<String, Object?>;
      expect(start['line'], 0);
      expect(start['character'], 11, reason: 'points at `lower`');
    });

    test('clears once the file is fixed', () async {
      await openDocument(client, 'composable lower {\n  Text("hi")\n}\n');
      expect(client.diagnosticsFor(testUri), hasLength(1));

      await client.notify('textDocument/didChange', {
        'textDocument': {'uri': testUri, 'version': 2},
        'contentChanges': [
          {'text': 'composable Upper {\n  Text("hi")\n}\n'},
        ],
      });

      expect(client.diagnosticsFor(testUri), isEmpty);
    });

    test('an incremental edit is applied, not just full replacements',
        () async {
      await openDocument(client, 'composable Ok {\n  Text("hi")\n}\n');
      expect(client.diagnosticsFor(testUri), isEmpty);

      // Replace `Ok` with `bad` using a ranged change.
      await client.notify('textDocument/didChange', {
        'textDocument': {'uri': testUri, 'version': 2},
        'contentChanges': [
          {
            'range': {
              'start': {'line': 0, 'character': 11},
              'end': {'line': 0, 'character': 13},
            },
            'text': 'bad',
          },
        ],
      });

      expect(client.diagnosticsFor(testUri), hasLength(1));
      expect(
        client.diagnosticsFor(testUri).single['message'],
        contains("composable 'bad'"),
      );
    });
  });

  group('hover', () {
    Future<String?> hoverText(String needle, {int occurrence = 0}) async {
      final result = await at(
        client,
        'textDocument/hover',
        _screen,
        needle,
        occurrence: occurrence,
      );
      if (result == null) return null;
      return ((result as Map)['contents'] as Map)['value'] as String;
    }

    test('documents a hook, including its trap', () async {
      final text = await hoverText('useState');
      expect(text, contains('StateRef<T> useState<T>(T initial)'));
      expect(text, contains('rebuilds the composable'));
    });

    test('documents a widget', () async {
      final text = await hoverText('Column');
      expect(text, contains('Vertical layout'));
      expect(text, contains('gap:'));
    });

    test('resolves a composable declared in the same file', () async {
      // The use site, not the declaration.
      final text = await hoverText('Badge', occurrence: 1);
      expect(text, contains('composable Badge'));
      expect(text, contains('label'));
    });

    test('shows the route for a page', () async {
      final text = await hoverText('InboxScreen');
      expect(text, contains('routed at `/inbox/:id`'));
    });

    test('shows a val and its expression', () async {
      final text = await hoverText('count');
      expect(text, contains('val count = useState(0)'));
    });

    test('resolves an enum shorthand to its full type', () async {
      final text = await hoverText('caption');
      expect(text, contains('Styles.caption'));
    });

    test('returns nothing for punctuation', () async {
      final result = await at(client, 'textDocument/hover', _screen, '{');
      expect(result, isNull);
    });
  });

  group('definition', () {
    test('jumps from a use site to the composable declaration', () async {
      final result = await at(
        client,
        'textDocument/definition',
        _screen,
        'Badge',
        occurrence: 1,
      ) as List;

      expect(result, hasLength(1));
      final location = result.single as Map<String, Object?>;
      expect(location['uri'], testUri);

      final start = (location['range']! as Map)['start']! as Map;
      expect(start['line'], 2, reason: 'the `composable Badge` line');
    });

    test('jumps to a val declaration', () async {
      final result = await at(
        client,
        'textDocument/definition',
        _screen,
        'count',
        occurrence: 1,
      ) as List;

      expect(result, hasLength(1));
      final start =
          ((result.single as Map)['range']! as Map)['start']! as Map;
      expect(start['line'], 9, reason: 'the `val count` line');
    });

    test('resolves across files', () async {
      const otherUri = 'file:///workspace/lib/pages/other.flx';
      await openDocument(
        client,
        'composable Elsewhere {\n  Text("there")\n}\n',
        uri: otherUri,
      );

      const usage = '''
composable Here {
  Column {
    Elsewhere()
  }
}
''';
      await openDocument(client, usage);

      final result = await at(
        client,
        'textDocument/definition',
        usage,
        'Elsewhere',
      ) as List;

      expect(result, hasLength(1));
      expect((result.single as Map)['uri'], otherUri);
    });

    test('returns nothing for an unknown name', () async {
      final result = await at(
        client,
        'textDocument/definition',
        _screen,
        'Text',
      ) as List;
      expect(result, isEmpty);
    });
  });

  group('document symbols', () {
    test('lists composables with their bindings nested', () async {
      final symbols = await client.request('textDocument/documentSymbol', {
        'textDocument': {'uri': testUri},
      }) as List;

      expect(symbols.map((s) => (s as Map)['name']), ['Badge', 'InboxScreen']);

      final inbox = symbols.last as Map<String, Object?>;
      expect(inbox['detail'], '@page("/inbox/:id")');
      expect(
        (inbox['children']! as List).map((c) => (c as Map)['name']),
        ['repo', 'count'],
      );
    });

    test('survives a file that no longer parses', () async {
      await client.notify('textDocument/didChange', {
        'textDocument': {'uri': testUri, 'version': 2},
        'contentChanges': [
          {'text': '$_screen\ncomposable Broken {'},
        ],
      });

      final symbols = await client.request('textDocument/documentSymbol', {
        'textDocument': {'uri': testUri},
      }) as List;

      // The outline lags rather than emptying — the alternative is a panel
      // that blinks out on every keystroke.
      expect(symbols, isNotEmpty);
      expect(symbols.map((s) => (s as Map)['name']), contains('InboxScreen'));
    });
  });

  group('workspace symbols', () {
    test('finds composables by fuzzy name', () async {
      final results =
          await client.request('workspace/symbol', {'query': 'inbox'}) as List;

      expect(results, hasLength(1));
      expect((results.single as Map)['name'], 'InboxScreen');
      expect((results.single as Map)['containerName'], '/inbox/:id');
    });

    test('an empty query returns everything', () async {
      final results =
          await client.request('workspace/symbol', {'query': ''}) as List;
      expect(results.map((r) => (r as Map)['name']),
          containsAll(['Badge', 'InboxScreen']));
    });
  });

  group('lifecycle', () {
    test('advertises the capabilities the client needs', () async {
      final fresh = TestClient();
      final result = await fresh.request('initialize', {'capabilities': {}})
          as Map<String, Object?>;
      final capabilities = result['capabilities']! as Map<String, Object?>;

      expect(capabilities['hoverProvider'], isTrue);
      expect(capabilities['definitionProvider'], isTrue);
      expect(capabilities['documentSymbolProvider'], isTrue);
      expect(
        (capabilities['textDocumentSync']! as Map)['change'],
        2,
        reason: 'incremental sync',
      );
      expect(
        (capabilities['completionProvider']! as Map)['triggerCharacters'],
        containsAll(['.', ':', '(']),
      );
      await fresh.close();
    });

    test('rejects requests made before initialize', () async {
      final fresh = TestClient();
      expect(
        () => fresh.request('textDocument/hover', {}),
        throwsA(isA<StateError>()),
      );
      await fresh.close();
    });

    test('an unknown method is an error, not a crash', () async {
      expect(
        () => client.request('textDocument/somethingElse', {}),
        throwsA(isA<StateError>()),
      );

      // The session still works afterwards.
      final symbols = await client.request('textDocument/documentSymbol', {
        'textDocument': {'uri': testUri},
      }) as List;
      expect(symbols, isNotEmpty);
    });

    test('requests for an unopened file return empty, not an error', () async {
      final result = await client.request('textDocument/documentSymbol', {
        'textDocument': {'uri': 'file:///nope.flx'},
      }) as List;
      expect(result, isEmpty);
    });

    test('closing a file clears its diagnostics', () async {
      await openDocument(client, 'composable lower {\n  Text("x")\n}\n');
      expect(client.diagnosticsFor(testUri), hasLength(1));

      await client.notify('textDocument/didClose', {
        'textDocument': {'uri': testUri},
      });
      expect(client.diagnosticsFor(testUri), isEmpty);
    });
  });
}
