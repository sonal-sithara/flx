import 'diagnostics.dart';
import 'source.dart';
import 'token.dart';

/// Multi-character operators, longest first so `??=` wins over `??`.
const _operators = <String>[
  '...',
  '??=',
  '>>=',
  '<<=',
  '===',
  '!==',
  '++',
  '--',
  '=>',
  '==',
  '!=',
  '<=',
  '>=',
  '&&',
  '||',
  '+=',
  '-=',
  '*=',
  '/=',
  '%=',
  '?.',
  '??',
  '::',
];

/// Turns `.flx` source into a token stream.
///
/// Unlike the Node prototype every token carries a [Span], which is what
/// makes real `file:line:col` diagnostics possible downstream.
class Lexer {
  Lexer(this.source);

  final Source source;
  String get _s => source.text;
  int _i = 0;

  List<Token> tokenize() {
    final tokens = <Token>[];
    while (true) {
      _skipTrivia();
      if (_i >= _s.length) break;
      tokens.add(_scanToken());
    }
    tokens.add(Token(TokenType.eof, '', Span(source, _s.length, _s.length)));
    return tokens;
  }

  void _skipTrivia() {
    while (_i < _s.length) {
      final c = _s[_i];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        _i++;
        continue;
      }
      // Line comment
      if (c == '/' && _peek(1) == '/') {
        while (_i < _s.length && _s[_i] != '\n') {
          _i++;
        }
        continue;
      }
      // Block comment, nesting like Dart's.
      if (c == '/' && _peek(1) == '*') {
        final start = _i;
        var depth = 0;
        while (_i < _s.length) {
          if (_s[_i] == '/' && _peek(1) == '*') {
            depth++;
            _i += 2;
          } else if (_s[_i] == '*' && _peek(1) == '/') {
            depth--;
            _i += 2;
            if (depth == 0) break;
          } else {
            _i++;
          }
        }
        if (depth != 0) {
          throw FlxError(
            'unterminated block comment',
            Span(source, start, start + 2),
            hint: "add a closing '*/'",
          );
        }
        continue;
      }
      return;
    }
  }

  String? _peek(int offset) {
    final j = _i + offset;
    return j < _s.length ? _s[j] : null;
  }

  Token _scanToken() {
    final start = _i;
    final c = _s[_i];

    // Raw strings: r"..." / r'...' lex as one token so they survive
    // round-tripping into Dart.
    if ((c == 'r') && (_peek(1) == '"' || _peek(1) == "'")) {
      _i++;
      _scanString(raw: true);
      return _token(TokenType.string, start);
    }

    if (c == '"' || c == "'") {
      _scanString(raw: false);
      return _token(TokenType.string, start);
    }

    if (_isDigit(c)) {
      while (_i < _s.length && (_isDigit(_s[_i]) || _s[_i] == '.')) {
        // Don't swallow the '.' of `1.toString()` style member access —
        // only consume it when a digit follows.
        if (_s[_i] == '.' && !_isDigit(_peek(1) ?? '')) break;
        _i++;
      }
      // Exponent / hex suffixes are rare in UI code but cheap to accept.
      if (_i < _s.length && (_s[_i] == 'e' || _s[_i] == 'E')) {
        final save = _i;
        _i++;
        if (_i < _s.length && (_s[_i] == '+' || _s[_i] == '-')) _i++;
        if (_i < _s.length && _isDigit(_s[_i])) {
          while (_i < _s.length && _isDigit(_s[_i])) {
            _i++;
          }
        } else {
          _i = save;
        }
      }
      return _token(TokenType.number, start);
    }

    if (_isIdentStart(c)) {
      while (_i < _s.length && _isIdentPart(_s[_i])) {
        _i++;
      }
      return _token(TokenType.identifier, start);
    }

    for (final op in _operators) {
      if (_s.startsWith(op, _i)) {
        _i += op.length;
        return _token(TokenType.punct, start);
      }
    }

    _i++;
    return _token(TokenType.punct, start);
  }

  /// Consumes a string literal starting at the quote, including any
  /// `${ ... }` interpolations — which may themselves contain strings and
  /// braces. The Node prototype scanned only for the next quote, so
  /// `"${m["k"]}"` terminated early and produced garbage Dart.
  void _scanString({required bool raw}) {
    final quoteStart = _i;
    final quote = _s[_i];
    // Triple-quoted?
    final triple = _s.startsWith(quote * 3, _i);
    final terminator = triple ? quote * 3 : quote;
    _i += terminator.length;

    while (true) {
      if (_i >= _s.length) {
        throw FlxError(
          'unterminated string literal',
          Span(source, quoteStart, quoteStart + terminator.length),
          hint: 'add a closing $terminator',
        );
      }
      if (!raw && _s[_i] == r'\') {
        _i += 2;
        continue;
      }
      if (!raw && _s[_i] == r'$' && _peek(1) == '{') {
        final interpolationStart = _i;
        _i += 2;
        _skipBalancedBraces(interpolationStart);
        continue;
      }
      if (_s.startsWith(terminator, _i)) {
        _i += terminator.length;
        return;
      }
      // A bare newline is legal in a triple-quoted string, an error otherwise.
      if (!triple && _s[_i] == '\n') {
        throw FlxError(
          'unterminated string literal',
          Span(source, quoteStart, quoteStart + 1),
          hint: 'strings cannot span lines — add a closing $quote, '
              'or use $terminator$terminator$terminator for a multi-line string',
        );
      }
      _i++;
    }
  }

  /// Skips to the `}` matching an already-consumed `${`, tracking nested
  /// braces and nested string literals.
  void _skipBalancedBraces(int interpolationStart) {
    Never unterminated() => throw FlxError(
          'unterminated interpolation in string literal',
          Span(source, interpolationStart, interpolationStart + 2),
          hint: r"add a closing '}' to the ${...} expression",
        );

    var depth = 1;
    while (depth > 0) {
      if (_i >= _s.length) unterminated();
      final c = _s[_i];
      if (c == r'\') {
        _i += 2;
        continue;
      }
      if (c == '"' || c == "'") {
        // A string inside the interpolation that never closes almost always
        // means the interpolation itself is missing its `}` — as in
        // `"hi ${name"`. Report that, not the inner quote.
        try {
          _scanString(raw: false);
        } on FlxError {
          unterminated();
        }
        continue;
      }
      if (c == '{') depth++;
      if (c == '}') depth--;
      _i++;
    }
  }

  Token _token(TokenType type, int start) =>
      Token(type, _s.substring(start, _i), Span(source, start, _i));

  static bool _isDigit(String c) => c.codeUnitAt(0) ^ 0x30 <= 9;

  static bool _isIdentStart(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 0x41 && u <= 0x5a) || // A-Z
        (u >= 0x61 && u <= 0x7a) || // a-z
        u == 0x5f || // _
        u == 0x24; // $
  }

  static bool _isIdentPart(String c) =>
      _isIdentStart(c) || (c.codeUnitAt(0) ^ 0x30) <= 9;
}
