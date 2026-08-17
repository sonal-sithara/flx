import 'source.dart';

/// A compile error with a source location. Thrown by the lexer, parser and
/// code generator; caught at the CLI boundary and printed with a caret.
class FlxError implements Exception {
  FlxError(this.message, this.span, {this.hint});

  final String message;
  final Span? span;

  /// Optional "here's what you probably meant" line. Worth writing whenever
  /// the mistake has an obvious fix — that is the difference between a
  /// prototype's `expected ) but got }` and a usable compiler.
  final String? hint;

  /// Full multi-line rendering:
  ///
  /// error: expected ')' to close the argument list
  ///   --> lib/pages/profile.flx:8:31
  ///    |
  ///  8 |     Avatar(user.photo, size: 64
  ///    |                               ^
  ///    = hint: add a ')' after the last argument
  String render() {
    final buf = StringBuffer('error: $message');
    final s = span;
    if (s != null) {
      buf.write('\n  --> ${s.location}\n');
      buf.write(s.render());
    }
    if (hint != null) buf.write('\n  = hint: $hint');
    return buf.toString();
  }

  @override
  String toString() => render();
}
