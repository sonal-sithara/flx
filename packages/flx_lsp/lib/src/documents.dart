import 'package:flx_compiler/flx_compiler.dart';

/// An open `.flx` file, plus conversion between LSP positions and offsets.
///
/// LSP positions are zero-based `{line, character}` where `character` counts
/// UTF-16 code units. Dart strings are already UTF-16, so string indices are
/// the right unit with no conversion — but line starts still have to be
/// recomputed on every edit, which is what [_lineStarts] caches.
class TextDocument {
  TextDocument({
    required this.uri,
    required String text,
    required this.version,
  })  : _text = text,
        _lineStarts = _computeLineStarts(text);

  final String uri;
  int version;

  String _text;
  List<int> _lineStarts;

  String get text => _text;
  int get lineCount => _lineStarts.length;

  /// Filesystem path, for diagnostics and for locating sibling files.
  String get path => uriToPath(uri);

  /// A flxc [Source] view of this document, so the compiler's lexer, parser
  /// and spans work against the in-memory buffer rather than what is on disk.
  Source get source => Source(path, _text);

  void update(String next, {int? newVersion}) {
    _text = next;
    _lineStarts = _computeLineStarts(next);
    if (newVersion != null) version = newVersion;
  }

  /// Applies one incremental change. A null [range] means a full replacement.
  void applyChange(Map<String, Object?>? range, String replacement) {
    if (range == null) {
      update(replacement);
      return;
    }
    final start = offsetAt(range['start']! as Map<String, Object?>);
    final end = offsetAt(range['end']! as Map<String, Object?>);
    update(_text.replaceRange(start, end, replacement));
  }

  static List<int> _computeLineStarts(String text) {
    final starts = <int>[0];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0a) starts.add(i + 1);
    }
    return starts;
  }

  /// LSP position → string offset, clamped so a stale position from a racing
  /// client cannot throw.
  int offsetAt(Map<String, Object?> position) {
    final line = (position['line'] as int? ?? 0).clamp(0, _lineStarts.length - 1);
    final character = position['character'] as int? ?? 0;

    final lineStart = _lineStarts[line];
    final lineEnd =
        line + 1 < _lineStarts.length ? _lineStarts[line + 1] - 1 : _text.length;
    return (lineStart + character).clamp(lineStart, lineEnd);
  }

  /// String offset → LSP position.
  Map<String, Object?> positionAt(int offset) {
    final clamped = offset.clamp(0, _text.length);
    var lo = 0;
    var hi = _lineStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_lineStarts[mid] <= clamped) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return {'line': lo, 'character': clamped - _lineStarts[lo]};
  }

  Map<String, Object?> rangeAt(int start, int end) =>
      {'start': positionAt(start), 'end': positionAt(end)};

  /// The LSP range covering a flxc [Span].
  Map<String, Object?> rangeOfSpan(Span span) =>
      rangeAt(span.start, span.end);

  /// Text of a zero-based line, without its newline.
  String lineAt(int line) {
    if (line < 0 || line >= _lineStarts.length) return '';
    final start = _lineStarts[line];
    final end =
        line + 1 < _lineStarts.length ? _lineStarts[line + 1] - 1 : _text.length;
    return _text.substring(start, end < start ? start : end);
  }
}

/// Every document the client currently has open.
class DocumentStore {
  final _documents = <String, TextDocument>{};

  Iterable<TextDocument> get all => _documents.values;

  TextDocument? operator [](String uri) => _documents[uri];

  bool get isEmpty => _documents.isEmpty;

  TextDocument open(String uri, String text, int version) {
    final document = TextDocument(uri: uri, text: text, version: version);
    _documents[uri] = document;
    return document;
  }

  void close(String uri) => _documents.remove(uri);
}

/// `file:///a/b.flx` → `/a/b.flx`, with percent-escapes decoded.
///
/// Written out rather than using Uri.parse().toFilePath() so a client sending
/// a non-file scheme, or a bare path, degrades to something usable instead of
/// throwing in the middle of a request.
String uriToPath(String uri) {
  if (!uri.startsWith('file://')) return uri;
  try {
    return Uri.parse(uri).toFilePath();
  } on Object {
    return Uri.decodeComponent(uri.substring('file://'.length));
  }
}

String pathToUri(String path) => Uri.file(path).toString();
