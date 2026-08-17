/// A source file plus the machinery to turn byte offsets into line/column
/// positions. Every token carries offsets; diagnostics turn those into the
/// `file:line:col` + caret output a compiler is expected to produce.
class Source {
  Source(this.path, this.text) : _lineStarts = _computeLineStarts(text);

  /// Path as the user typed it — used verbatim in diagnostics so the
  /// output is clickable in a terminal.
  final String path;
  final String text;

  /// Offset of the first character of each line.
  final List<int> _lineStarts;

  static List<int> _computeLineStarts(String text) {
    final starts = <int>[0];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0a) starts.add(i + 1);
    }
    return starts;
  }

  int get lineCount => _lineStarts.length;

  /// 1-based line number containing [offset]. Binary search.
  int lineAt(int offset) {
    var lo = 0;
    var hi = _lineStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_lineStarts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo + 1;
  }

  /// 1-based column of [offset].
  int columnAt(int offset) => offset - _lineStarts[lineAt(offset) - 1] + 1;

  /// Text of a 1-based [line], without its trailing newline.
  String lineText(int line) {
    final start = _lineStarts[line - 1];
    final end = line < _lineStarts.length ? _lineStarts[line] - 1 : text.length;
    // Guard against a trailing \r on CRLF files.
    if (end > start && text.codeUnitAt(end - 1) == 0x0d) {
      return text.substring(start, end - 1);
    }
    return text.substring(start, end < start ? start : end);
  }
}

/// A half-open range `[start, end)` within a [Source].
class Span {
  const Span(this.source, this.start, this.end);

  final Source source;
  final int start;
  final int end;

  int get line => source.lineAt(start);
  int get column => source.columnAt(start);

  /// `path:line:col` — the form editors and terminals linkify.
  String get location => '${source.path}:$line:$column';

  /// Renders the offending line with a caret underlining this span:
  ///
  ///    |
  ///  8 |     Avatar(user.photo, size: 64
  ///    |                             ^^
  String render() {
    final ln = line;
    final text = source.lineText(ln);
    final gutter = '$ln';
    final pad = ' ' * gutter.length;
    // Underline the span, but never run past the end of the line.
    final col = column;
    final maxLen = text.length - (col - 1);
    final len = (end - start).clamp(1, maxLen < 1 ? 1 : maxLen);
    final caret = '${' ' * (col - 1)}${'^' * len}';
    return '$pad |\n'
        '$gutter | $text\n'
        '$pad | $caret';
  }
}
