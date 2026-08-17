import 'token.dart';

/// Nothing gets a space before these.
const _tightBefore = {
  ',', ')', ']', '}', '.', '?.', '(', '[', ';', '!', '++', '--', ':',
};

/// Nothing gets a space after these.
const _tightAfter = {'.', '?.', '(', '[', '{', '!', '@'};

/// Tokens allowed inside a generic argument list. Used to tell
/// `useState<int>(0)` apart from `a < b`.
const _typeTokens = {',', '.', '<', '>', '?', '(', ')'};

/// Renders a token slice back into Dart source.
///
/// The DSL deliberately does not parse expressions — anything that isn't
/// widget-tree structure is passed through to Dart, which is the real type
/// checker. This just needs to re-insert whitespace so the output is valid
/// and readable.
String serialize(List<Token> tokens) {
  final generics = _findGenerics(tokens);
  final ternaryColons = _findTernaryColons(tokens);
  final buf = StringBuffer();

  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    final lexeme = t.lexeme;

    if (i > 0) {
      final prev = tokens[i - 1];
      final inGeneric = generics.contains(i) || generics.contains(i - 1);
      // `a ? b : c` breathes; `name: value` does not.
      if (ternaryColons.contains(i)) {
        buf.write(' ');
      } else if (!inGeneric && _needsSpace(prev, t)) {
        buf.write(' ');
      }
    }
    buf.write(lexeme);
  }
  return buf.toString();
}

/// Indices of `:` tokens that close a conditional expression rather than
/// introduce a named argument or a map entry.
///
/// A `?` at the same nesting depth arms the next `:`. Both spellings are valid
/// Dart, but `cond ? a: b` reads as a typo, and generated code is meant to be
/// read.
Set<int> _findTernaryColons(List<Token> tokens) {
  final marked = <int>{};
  final armed = <int>[]; // one counter per nesting depth
  var depth = 0;
  armed.add(0);

  for (var i = 0; i < tokens.length; i++) {
    final lexeme = tokens[i].lexeme;

    if (lexeme == '(' || lexeme == '[' || lexeme == '{') {
      depth++;
      if (armed.length <= depth) armed.add(0);
      armed[depth] = 0;
      continue;
    }
    if (lexeme == ')' || lexeme == ']' || lexeme == '}') {
      if (depth > 0) depth--;
      continue;
    }
    // `?.` and `??` are operators, not conditionals. A `?` closing a nullable
    // type is followed by a name or `>`, never by an expression needing `:`.
    if (lexeme == '?') {
      armed[depth]++;
      continue;
    }
    if (lexeme == ':' && armed[depth] > 0) {
      armed[depth]--;
      marked.add(i);
    }
  }
  return marked;
}

bool _needsSpace(Token prev, Token t) {
  // A comma always breathes, except when the list closes right after it
  // (a trailing comma before `)` or `]`).
  if (prev.lexeme == ',') return t.lexeme != ')' && t.lexeme != ']';
  // `keys: [...]`, `{'a': 1}`, `cond ? a : b` — a colon always breathes too.
  if (prev.lexeme == ':') return true;
  if (_tightBefore.contains(t.lexeme)) return false;
  if (_tightAfter.contains(prev.lexeme)) return false;
  return true;
}

/// Returns the indices of every token that is part of a generic argument
/// list, so `<`, the type names and `>` are packed tightly.
///
/// The heuristic: a `<` directly following an identifier opens a generic if a
/// matching `>` can be reached through type-ish tokens only. Otherwise it is
/// a comparison operator and gets normal spacing.
Set<int> _findGenerics(List<Token> tokens) {
  final marked = <int>{};

  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i].lexeme != '<') continue;
    if (i == 0 || tokens[i - 1].type != TokenType.identifier) continue;
    if (marked.contains(i)) continue;

    var depth = 0;
    final candidate = <int>[];
    for (var j = i; j < tokens.length; j++) {
      final lex = tokens[j].lexeme;
      final isTypeish =
          tokens[j].type == TokenType.identifier || _typeTokens.contains(lex);
      if (!isTypeish) break;

      candidate.add(j);
      if (lex == '<') depth++;
      if (lex == '>') {
        depth--;
        if (depth == 0) {
          // Include the identifier that opened the generic so `useState<int>`
          // has no space before `<`.
          marked
            ..add(i - 1)
            ..addAll(candidate);
          break;
        }
      }
    }
  }
  return marked;
}
