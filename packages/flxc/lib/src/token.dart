import 'source.dart';

enum TokenType { identifier, string, number, punct, eof }

class Token {
  const Token(this.type, this.lexeme, this.span);

  final TokenType type;

  /// The exact source text of this token. Strings keep their quotes and
  /// interpolations intact so they can be re-emitted into Dart verbatim.
  final String lexeme;
  final Span span;

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
