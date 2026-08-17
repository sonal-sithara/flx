import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// JSON-RPC 2.0 over the LSP base protocol: each message is a
/// `Content-Length: N` header, a blank line, then N bytes of UTF-8 JSON.
///
/// Framing is done over bytes rather than decoded text on purpose — the
/// header counts bytes, and a single non-ASCII character in a document would
/// desynchronise a character-based reader for the rest of the session.
class LspConnection {
  LspConnection(this._input, this._write);

  final Stream<List<int>> _input;
  final void Function(List<int> bytes) _write;

  final _buffer = BytesBuilder(copy: false);
  final _messages = StreamController<Map<String, Object?>>();

  /// Decoded incoming messages, in arrival order.
  Stream<Map<String, Object?>> get messages => _messages.stream;

  StreamSubscription<List<int>>? _subscription;

  void listen() {
    _subscription = _input.listen(
      _onData,
      onDone: _messages.close,
      onError: _messages.addError,
    );
  }

  Future<void> close() async {
    await _subscription?.cancel();
    if (!_messages.isClosed) await _messages.close();
  }

  void _onData(List<int> chunk) {
    _buffer.add(chunk);
    _drain();
  }

  /// Pulls every complete message out of the buffer, leaving any partial one.
  void _drain() {
    var bytes = _buffer.toBytes();
    var consumed = 0;

    while (true) {
      final headerEnd = _findHeaderEnd(bytes, consumed);
      if (headerEnd < 0) break;

      final header = utf8.decode(
        bytes.sublist(consumed, headerEnd),
        allowMalformed: true,
      );
      final length = _contentLength(header);
      if (length == null) {
        // Unparseable header: skip it rather than stalling forever.
        consumed = headerEnd + 4;
        continue;
      }

      final bodyStart = headerEnd + 4;
      if (bytes.length < bodyStart + length) break; // wait for more bytes

      final body = utf8.decode(bytes.sublist(bodyStart, bodyStart + length));
      consumed = bodyStart + length;

      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, Object?>) _messages.add(decoded);
      } on FormatException {
        // A malformed body is dropped; the stream stays in sync because the
        // header already told us exactly how many bytes to skip.
      }
    }

    if (consumed > 0) {
      final rest = bytes.sublist(consumed);
      _buffer
        ..clear()
        ..add(rest);
    }
  }

  /// Index of the `\r\n\r\n` that ends the header block, or -1.
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

  static int? _contentLength(String header) {
    for (final line in header.split('\r\n')) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      if (line.substring(0, colon).trim().toLowerCase() != 'content-length') {
        continue;
      }
      return int.tryParse(line.substring(colon + 1).trim());
    }
    return null;
  }

  void _send(Map<String, Object?> message) {
    final body = utf8.encode(jsonEncode(message));
    _write(utf8.encode('Content-Length: ${body.length}\r\n\r\n'));
    _write(body);
  }

  /// A successful response to a request.
  void respond(Object id, Object? result) =>
      _send({'jsonrpc': '2.0', 'id': id, 'result': result});

  void respondError(Object id, int code, String message) => _send({
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      });

  /// A server-initiated notification, such as publishDiagnostics.
  void notify(String method, Map<String, Object?> params) =>
      _send({'jsonrpc': '2.0', 'method': method, 'params': params});
}

/// The subset of JSON-RPC error codes this server produces.
abstract final class LspErrorCode {
  static const parseError = -32700;
  static const methodNotFound = -32601;
  static const invalidParams = -32602;
  static const internalError = -32603;
  static const serverNotInitialized = -32002;
}
