import 'source.dart';

enum TokenType { identifier, string, number, punct, eof }

class Token {
  Token(this.type, this.lexeme, this.span);

  final TokenType type;

  /// The exact source text of this token. Strings keep their quotes and
  /// interpolations intact so they can be re-emitted into Dart verbatim.
  final String lexeme;
  final Span span;

  /// Set by the serializer: true when this `-`/`+` is a sign rather than a
  /// binary operator, so it binds tightly to the number after it.
  bool isUnary = false;

  bool get isEof => type == TokenType.eof;

  /// Convenience for the parser's very common `tok.value == '{'` checks.
  bool is_(String value) => lexeme == value;

  bool isIdent(String value) =>
      type == TokenType.identifier && lexeme == value;

  /// How this token should be named in an error message.
  String get describe => switch (type) {
        TokenType.eof => 'end of file',
        TokenType.string => 'a string',
        TokenType.number => "number '$lexeme'",
        _ => "'$lexeme'",
      };

  @override
  String toString() => '${type.name}($lexeme)';
}
