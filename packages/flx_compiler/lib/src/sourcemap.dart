import 'diagnostics.dart';
import 'lexer.dart';
import 'source.dart';
import 'token.dart';

/// How sure the mapper is that a Dart location corresponds to a `.flx` one.
enum MapConfidence {
  /// The identifier appears the same number of times in both files, and the
  /// occurrence indices line up.
  exact,

  /// The identifier appears exactly once in the `.flx`, so there is nowhere
  /// else it could be, even though the counts differ.
  unique,

  /// No correspondence found — report the generated location instead.
  none,
}

class MappedLocation {
  const MappedLocation(this.span, this.confidence);

  const MappedLocation.unmapped()
      : span = null,
        confidence = MapConfidence.none;

  final Span? span;
  final MapConfidence confidence;

  bool get isMapped => span != null;
}

/// Maps a location in generated Dart back to the `.flx` that produced it.
///
/// Rather than threading spans through code generation, this exploits a
/// property of the generator: user identifiers are emitted in source order and
/// never reordered. So the *n*th `foo` in the Dart is the *n*th `foo` in the
/// `.flx`.
///
/// That is a heuristic, and it is treated as one — [MapConfidence] says how
/// much to trust each result, and an unmappable location reports the generated
/// file rather than guessing. It handles the cases that actually happen: a
/// misspelled method, an unknown name, a wrong argument label.
///
/// Identifiers inside string literals are invisible to both sides equally
/// (they live inside a string token), so interpolations do not skew the count.
class SourceMapper {
  SourceMapper(this.flx, this.dart)
      : _flxTokens = _identifiers(flx),
        _dartTokens = _identifiers(dart);

  final Source flx;
  final Source dart;

  final List<Token> _flxTokens;
  final List<Token> _dartTokens;

  static List<Token> _identifiers(Source source) {
    try {
      return Lexer(source)
          .tokenize()
          .where((t) => t.type == TokenType.identifier)
          .toList();
    } on FlxError {
      return const [];
    }
  }

  /// Maps a zero-based offset in the generated Dart.
  MappedLocation map(int dartOffset) {
    final token = _tokenAt(_dartTokens, dartOffset);
    if (token == null) return const MappedLocation.unmapped();

    final direct = _mapName(token.lexeme, token);
    if (direct.isMapped) return direct;

    // `useFetch` results are emitted as `name$`; the DSL only ever wrote
    // `name`.
    if (token.lexeme.endsWith(r'$')) {
      return _mapName(
        token.lexeme.substring(0, token.lexeme.length - 1),
        token,
      );
    }
    return const MappedLocation.unmapped();
  }

  /// Maps a 1-based line/column pair, as reported by `dart analyze`.
  MappedLocation mapLineColumn(int line, int column) {
    if (line < 1 || line > dart.lineCount) return const MappedLocation.unmapped();
    final lineStart = _offsetOfLine(line);
    return map(lineStart + column - 1);
  }

  MappedLocation _mapName(String name, Token dartToken) {
    final inDart = [
      for (final t in _dartTokens)
        if (t.lexeme == dartToken.lexeme) t,
    ];
    final inFlx = [
      for (final t in _flxTokens)
        if (t.lexeme == name) t,
    ];
    if (inFlx.isEmpty) return const MappedLocation.unmapped();

    // Nowhere else it could be.
    if (inFlx.length == 1) {
      return MappedLocation(inFlx.single.span, MapConfidence.unique);
    }

    final index = inDart.indexWhere((t) => t.span.start == dartToken.span.start);
    if (index >= 0 && inDart.length == inFlx.length) {
      return MappedLocation(inFlx[index].span, MapConfidence.exact);
    }
    // Counts differ — generated boilerplate mentions the name too. Falling
    // back to an arbitrary occurrence would point at the wrong line, which is
    // worse than pointing at the generated file.
    return const MappedLocation.unmapped();
  }

  int _offsetOfLine(int line) {
    var current = 1;
    for (var i = 0; i < dart.text.length; i++) {
      if (current == line) return i;
      if (dart.text.codeUnitAt(i) == 0x0a) current++;
    }
    return dart.text.length;
  }

  static Token? _tokenAt(List<Token> tokens, int offset) {
    for (final token in tokens) {
      if (offset >= token.span.start && offset < token.span.end) return token;
    }
    // The analyzer sometimes points just past a name; accept an exact end.
    for (final token in tokens) {
      if (offset == token.span.end) return token;
    }
    return null;
  }
}
