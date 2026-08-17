import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flx_lsp/src/protocol.dart';
import 'package:flx_lsp/src/server.dart';

/// Drives a real [FlxLanguageServer] over the real framing, so the tests
/// exercise the same path an editor does — not the handler methods directly.
class TestClient {
  TestClient() {
    final connection = LspConnection(_input.stream, _output.add);
    server = FlxLanguageServer(connection);
    unawaited(server.serve());
  }

  final _input = StreamController<List<int>>();
  final _output = BytesBuilder(copy: false);
  late final FlxLanguageServer server;

  int _nextId = 0;
  int _consumed = 0;
  final _received = <Map<String, Object?>>[];

  Future<void> close() => _input.close();

  /// Lets the server drain everything queued. Handling is synchronous, so a
  /// handful of microtask turns is always enough.
  Future<void> settle() async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    _readOutput();
  }

  void _sendRaw(Map<String, Object?> message) {
    final body = utf8.encode(jsonEncode(message));
    _input
      ..add(utf8.encode('Content-Length: ${body.length}\r\n\r\n'))
      ..add(body);
  }

  /// Sends a request and returns its `result`.
  Future<Object?> request(String method, [Map<String, Object?>? params]) async {
    final id = ++_nextId;
    _sendRaw({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params ?? const {},
    });
    await settle();

    for (final message in _received.reversed) {
      if (message['id'] == id) {
        if (message.containsKey('error')) {
          throw StateError('server error: ${message['error']}');
        }
        return message['result'];
      }
    }
    throw StateError('no response to $method');
  }

  Future<void> notify(String method, Map<String, Object?> params) async {
    _sendRaw({'jsonrpc': '2.0', 'method': method, 'params': params});
    await settle();
  }

  /// Every notification the server has sent, in order.
  List<Map<String, Object?>> notificationsOf(String method) => [
        for (final message in _received)
          if (message['method'] == method)
            message['params']! as Map<String, Object?>,
      ];

  /// The most recent diagnostics published for [uri].
  List<Map<String, Object?>> diagnosticsFor(String uri) {
    for (final params in notificationsOf('textDocument/publishDiagnostics').reversed) {
      if (params['uri'] == uri) {
        return [
          for (final d in params['diagnostics']! as List)
            d as Map<String, Object?>,
        ];
      }
    }
    return const [];
  }

  void _readOutput() {
    final bytes = _output.toBytes();
    while (true) {
      final headerEnd = _findHeaderEnd(bytes, _consumed);
      if (headerEnd < 0) return;

      final header = utf8.decode(bytes.sublist(_consumed, headerEnd));
      final match = RegExp(r'Content-Length:\s*(\d+)').firstMatch(header);
      if (match == null) return;

      final length = int.parse(match.group(1)!);
      final start = headerEnd + 4;
      if (bytes.length < start + length) return;

      _received.add(
        jsonDecode(utf8.decode(bytes.sublist(start, start + length)))
            as Map<String, Object?>,
      );
      _consumed = start + length;
    }
  }

  static int _findHeaderEnd(Uint8List bytes, int from) {
    for (var i = from; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }
}

/// Boots a client through `initialize` with no workspace root.
Future<TestClient> startedClient() async {
  final client = TestClient();
  await client.request('initialize', {'rootUri': null, 'capabilities': {}});
  await client.notify('initialized', {});
  return client;
}

const testUri = 'file:///workspace/lib/pages/test.flx';

/// Opens a document and returns the client.
Future<void> openDocument(
  TestClient client,
  String text, {
  String uri = testUri,
}) =>
    client.notify('textDocument/didOpen', {
      'textDocument': {
        'uri': uri,
        'languageId': 'flx',
        'version': 1,
        'text': text,
      },
    });

/// Offset of `|` in [text], with the marker removed.
({String text, int offset}) cursor(String marked) {
  final offset = marked.indexOf('|');
  if (offset < 0) throw ArgumentError('no | marker in: $marked');
  return (text: marked.replaceFirst('|', ''), offset: offset);
}

/// Converts an offset into the LSP position the client would send.
Map<String, Object?> positionOf(String text, int offset) {
  var line = 0;
  var lineStart = 0;
  for (var i = 0; i < offset && i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0a) {
      line++;
      lineStart = i + 1;
    }
  }
  return {'line': line, 'character': offset - lineStart};
}

/// Sends [method] positioned on the [occurrence]th match of [needle] in
/// [text] — the way a reader puts the caret on a name and presses F12.
Future<Object?> at(
  TestClient client,
  String method,
  String text,
  Pattern needle, {
  int occurrence = 0,
  String uri = testUri,
}) async {
  var index = -1;
  for (var i = 0; i <= occurrence; i++) {
    index = text.indexOf(needle, index + 1);
    if (index < 0) throw ArgumentError('no match $occurrence for $needle');
  }
  return client.request(method, {
    'textDocument': {'uri': uri},
    'position': positionOf(text, index + 1),
  });
}

/// Requests completion at the `|` marker and returns the item labels.
Future<List<String>> completionLabels(TestClient client, String marked) async {
  final (:text, :offset) = cursor(marked);
  await openDocument(client, text);
  final result = await client.request('textDocument/completion', {
    'textDocument': {'uri': testUri},
    'position': positionOf(text, offset),
  }) as Map<String, Object?>;

  return [
    for (final item in result['items']! as List)
      (item as Map<String, Object?>)['label']! as String,
  ];
}
