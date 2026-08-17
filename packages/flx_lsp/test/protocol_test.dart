import 'dart:async';
import 'dart:convert';

import 'package:flx_lsp/src/protocol.dart';
import 'package:test/test.dart';

/// Framing is the one place a bug corrupts the whole session rather than one
/// request, so it is tested against the awkward cases directly.
void main() {
  late StreamController<List<int>> input;
  late List<int> written;
  late LspConnection connection;

  setUp(() {
    input = StreamController<List<int>>();
    written = [];
    connection = LspConnection(input.stream, written.addAll)..listen();
  });

  tearDown(() async {
    await input.close();
    await connection.close();
  });

  List<int> frame(Object message) {
    final body = utf8.encode(jsonEncode(message));
    return [...utf8.encode('Content-Length: ${body.length}\r\n\r\n'), ...body];
  }

  Future<List<Map<String, Object?>>> collect(
    void Function() send, {
    int expected = 1,
  }) async {
    final received = <Map<String, Object?>>[];
    final subscription = connection.messages.listen(received.add);
    send();
    for (var i = 0; i < 10 && received.length < expected; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await subscription.cancel();
    return received;
  }

  group('reading', () {
    test('decodes a single message', () async {
      final messages = await collect(
        () => input.add(frame({'method': 'ping', 'id': 1})),
      );

      expect(messages, hasLength(1));
      expect(messages.single['method'], 'ping');
    });

    test('decodes several messages arriving in one chunk', () async {
      final messages = await collect(
        () => input.add([
          ...frame({'method': 'a'}),
          ...frame({'method': 'b'}),
          ...frame({'method': 'c'}),
        ]),
        expected: 3,
      );

      expect(messages.map((m) => m['method']), ['a', 'b', 'c']);
    });

    test('reassembles a message split across chunks', () async {
      final bytes = frame({'method': 'split', 'id': 7});
      final messages = await collect(() {
        // Byte by byte — the worst case a pipe can deliver.
        for (final byte in bytes) {
          input.add([byte]);
        }
      });

      expect(messages, hasLength(1));
      expect(messages.single['id'], 7);
    });

    test('counts bytes, not characters', () async {
      // 'é' and the emoji are multi-byte in UTF-8. A character-based reader
      // would desynchronise here and never recover.
      final messages = await collect(
        () => input.add([
          ...frame({'text': 'café 🎉 ünïcödé'}),
          ...frame({'method': 'after'}),
        ]),
        expected: 2,
      );

      expect(messages.first['text'], 'café 🎉 ünïcödé');
      expect(messages.last['method'], 'after',
          reason: 'the stream stayed in sync');
    });

    test('is not confused by a body containing the header sequence', () async {
      final messages = await collect(
        () => input.add([
          ...frame({'text': 'Content-Length: 999\r\n\r\nnot a real header'}),
          ...frame({'method': 'after'}),
        ]),
        expected: 2,
      );

      expect(messages.last['method'], 'after');
    });

    test('skips a malformed body without losing the next message', () async {
      final broken = utf8.encode('{not json');
      final messages = await collect(
        () => input.add([
          ...utf8.encode('Content-Length: ${broken.length}\r\n\r\n'),
          ...broken,
          ...frame({'method': 'survivor'}),
        ]),
      );

      expect(messages, hasLength(1));
      expect(messages.single['method'], 'survivor');
    });

    test('tolerates extra headers', () async {
      final body = utf8.encode(jsonEncode({'method': 'typed'}));
      final messages = await collect(
        () => input.add([
          ...utf8.encode(
            'Content-Length: ${body.length}\r\n'
            'Content-Type: application/vscode-jsonrpc; charset=utf-8\r\n\r\n',
          ),
          ...body,
        ]),
      );

      expect(messages.single['method'], 'typed');
    });

    test('waits for an incomplete body rather than emitting a partial', () async {
      final messages = await collect(() {
        input.add(utf8.encode('Content-Length: 100\r\n\r\n{"a":1}'));
      }, expected: 0);

      expect(messages, isEmpty);
    });
  });

  group('writing', () {
    String output() => utf8.decode(written);

    test('frames a response with a byte count', () {
      connection.respond(3, {'ok': true});
      final text = output();

      final length = int.parse(
        RegExp(r'Content-Length: (\d+)').firstMatch(text)!.group(1)!,
      );
      final body = text.substring(text.indexOf('\r\n\r\n') + 4);
      expect(utf8.encode(body).length, length);
      expect(jsonDecode(body), {'jsonrpc': '2.0', 'id': 3, 'result': {'ok': true}});
    });

    test('counts bytes for non-ASCII payloads', () {
      connection.notify('window/logMessage', {'message': 'built 🎉'});
      final text = output();

      final length = int.parse(
        RegExp(r'Content-Length: (\d+)').firstMatch(text)!.group(1)!,
      );
      final body = text.substring(text.indexOf('\r\n\r\n') + 4);
      expect(utf8.encode(body).length, length);
      expect(length, greaterThan(body.length),
          reason: 'the emoji takes more bytes than code units');
    });

    test('errors carry a code and message', () {
      connection.respondError(9, LspErrorCode.methodNotFound, 'nope');
      final body = output().substring(output().indexOf('\r\n\r\n') + 4);

      expect(jsonDecode(body), {
        'jsonrpc': '2.0',
        'id': 9,
        'error': {'code': -32601, 'message': 'nope'},
      });
    });
  });
}
