import 'package:flx_compiler/flx_compiler.dart';

import 'analysis.dart';
import 'catalog.dart';
import 'dart_index.dart';

/// LSP SymbolKind values, named.
abstract final class SymbolKind {
  static const $class = 5;
  static const method = 6;
  static const property = 7;
  static const field = 8;
  static const variable = 13;
}

/// The token whose span contains [offset], or the one ending exactly at it —
/// so hovering the last character of a name still resolves.
///
/// A string literal is a single token, but `"Seen \${count.value}"` contains
/// real code. `.flx` refers to its bindings from inside interpolations
/// constantly, so the string is re-lexed to find the identifier actually
/// under the cursor.
Token? tokenAt(Analysis analysis, int offset) {
  for (final token in analysis.tokens) {
    if (token.isEof) continue;
    if (offset < token.span.start || offset > token.span.end) continue;
    if (token.type == TokenType.string) {
      return _insideInterpolation(analysis, token, offset) ?? token;
    }
    return token;
  }
  return null;
}

/// The token at [offset] within a `\${ ... }` region of [string], with its
/// span translated back into the enclosing document.
Token? _insideInterpolation(Analysis analysis, Token string, int offset) {
  final text = string.lexeme;
  final source = analysis.document.source;

  for (var i = 0; i + 1 < text.length; i++) {
    if (text[i] == r'\') {
      i++;
      continue;
    }
    if (text[i] != r'$' || text[i + 1] != '{') continue;

    var depth = 1;
    var j = i + 2;
    while (j < text.length && depth > 0) {
      if (text[j] == '{') depth++;
      if (text[j] == '}') depth--;
      j++;
    }

    final contentStart = string.span.start + i + 2;
    final contentEnd = string.span.start + (depth == 0 ? j - 1 : j);
    if (offset < contentStart || offset > contentEnd) {
      i = j - 1;
      continue;
    }

    final content = text.substring(i + 2, depth == 0 ? j - 1 : j);
    final List<Token> inner;
    try {
      inner = Lexer(Source(source.path, content)).tokenize();
    } on FlxError {
      return null;
    }

    final local = offset - contentStart;
    for (final token in inner) {
      if (token.isEof) continue;
      if (local < token.span.start || local > token.span.end) continue;
      return Token(
        token.type,
        token.lexeme,
        Span(
          source,
          contentStart + token.span.start,
          contentStart + token.span.end,
        ),
      );
    }
    return null;
  }
  return null;
}

/// Markdown hover card for the symbol under the cursor.
Map<String, Object?>? hoverAt(
  Workspace workspace,
  Analysis analysis,
  int offset,
) {
  final token = tokenAt(analysis, offset);
  if (token == null || token.type != TokenType.identifier) return null;

  final document = analysis.document;
  final range = document.rangeOfSpan(token.span);

  final known = symbolsByName[token.lexeme];
  if (known != null) {
    return _hover(
      '```dart\n${known.signature}\n```\n\n${known.documentation}',
      range,
    );
  }

  // A composable declared anywhere in the workspace.
  final composable = workspace.findComposable(
    token.lexeme,
    preferUri: analysis.document.uri,
  );
  if (composable != null) {
    final decl = composable.decl;
    final params = decl.params
        .map((p) => '${p.type} ${p.name}')
        .join(', ');
    final buffer = StringBuffer('```flx\ncomposable ${decl.name}');
    if (decl.params.isNotEmpty) buffer.write('($params)');
    buffer.write('\n```');
    if (decl.isPage) {
      buffer.write('\n\nA screen, routed at `${decl.route}`.');
    }
    if (decl.vals.isNotEmpty) {
      buffer.write('\n\nBindings: ${decl.vals.map((v) => '`${v.name}`').join(', ')}');
    }
    return _hover(buffer.toString(), range);
  }

  // A `val` in the enclosing composable.
  final binding = _bindingNamed(analysis, token.lexeme);
  if (binding != null) {
    return _hover(
      '```dart\nval ${binding.name} = ${binding.expr}\n```'
      '${binding.isAsync ? '\n\nA `useFetch` binding: below the widget tree this '
          'is the resolved value. Elsewhere use `${binding.name}\$`.' : ''}',
      range,
    );
  }

  // Enum shorthands: `main: .center`.
  final argument = _argumentBefore(analysis, token);
  if (argument != null) {
    final entry = shorthandValues[argument];
    if (entry != null) {
      final (type, _) = entry;
      return _hover('```dart\n$type.${token.lexeme}\n```', range);
    }
  }
  return null;
}

Map<String, Object?> _hover(String markdown, Map<String, Object?> range) => {
      'contents': {'kind': 'markdown', 'value': markdown},
      'range': range,
    };

ValDecl? _bindingNamed(Analysis analysis, String name) {
  final ast = analysis.ast;
  if (ast == null) return null;
  for (final composable in ast.composables) {
    for (final val in composable.vals) {
      if (val.name == name) return val;
    }
  }
  return null;
}

/// The argument name a `.shorthand` token belongs to, if any.
String? _argumentBefore(Analysis analysis, Token token) {
  final tokens = analysis.tokens;
  var index = tokens.indexOf(token);
  if (index < 0) {
    // Tokens recovered from inside an interpolation are new objects.
    index = tokens.indexWhere((t) => t.span.start == token.span.start);
  }
  if (index < 2) return null;
  if (tokens[index - 1].lexeme != '.') return null;
  if (tokens[index - 2].lexeme != ':') return null;
  if (index < 3 || tokens[index - 3].type != TokenType.identifier) return null;
  return tokens[index - 3].lexeme;
}

/// Go-to-definition.
///
/// Three kinds of name, in the order Dart itself would resolve them: a
/// composable anywhere in the workspace, a `val` or parameter in this file,
/// and — through [dartIndex] — the Dart underneath, which is where the hooks
/// and the widgets live.
List<Map<String, Object?>> definitionAt(
  Workspace workspace,
  Analysis analysis,
  int offset, {
  DartIndex? dartIndex,
}) {
  final token = tokenAt(analysis, offset);
  if (token == null || token.type != TokenType.identifier) return const [];

  final composable = workspace.findComposable(
    token.lexeme,
    preferUri: analysis.document.uri,
  );
  if (composable != null) {
    final target = workspace[composable.uri];
    if (target != null) {
      return [
        {
          'uri': composable.uri,
          'range': target.document.rangeOfSpan(composable.decl.span),
        },
      ];
    }
  }

  // A `val` in this file.
  final ast = analysis.ast;
  if (ast != null) {
    for (final decl in ast.composables) {
      for (final val in decl.vals) {
        if (val.name != token.lexeme) continue;
        return [
          {
            'uri': analysis.document.uri,
            'range': analysis.document.rangeOfSpan(val.span),
          },
        ];
      }
      for (final param in decl.params) {
        if (param.name != token.lexeme) continue;
        return [
          {
            'uri': analysis.document.uri,
            'range': analysis.document.rangeOfSpan(param.span),
          },
        ];
      }
    }
  }

  // A hook, a widget, a ViewModel — anything declared in Dart.
  if (dartIndex != null && _isPlainReference(analysis, token)) {
    final symbols = dartIndex.lookup(token.lexeme);
    if (symbols.isNotEmpty) {
      return [
        // Several packages can declare the same name. The editor shows them
        // all rather than picking one silently, best candidate first.
        for (final symbol in symbols.take(_maxDartCandidates)) symbol.location,
      ];
    }
  }
  return const [];
}

/// At most this many Dart candidates for one name.
///
/// A name like `Text` is declared in half the packages a Flutter app pulls in.
/// Ten is enough for the real answer to be in the list and few enough that the
/// list is still readable.
const _maxDartCandidates = 10;

/// Whether [token] is a name in its own right, rather than a member being read
/// off something else or an argument label.
///
/// `vm.setSearch(...)` must not jump to some unrelated top-level `setSearch`,
/// and neither must the `style` in `style: .caption`. The index only holds
/// top-level declarations, so in both cases a hit would be a coincidence.
bool _isPlainReference(Analysis analysis, Token token) {
  final tokens = analysis.tokens;
  var index = tokens.indexOf(token);
  if (index < 0) {
    index = tokens.indexWhere((t) => t.span.start == token.span.start);
  }
  if (index < 0) return true;
  if (index > 0 && tokens[index - 1].lexeme == '.') return false;
  if (index + 1 < tokens.length && tokens[index + 1].lexeme == ':') return false;
  return true;
}

/// Outline: composables, with their bindings nested underneath.
///
/// Built from the last successful parse, which may be slightly stale — an
/// outline that empties itself on every keystroke is worse than one that lags.
List<Map<String, Object?>> documentSymbols(Analysis analysis) {
  final ast = analysis.ast;
  if (ast == null) return const [];
  final document = analysis.document;

  return [
    for (final decl in ast.composables)
      {
        'name': decl.name,
        'detail': decl.isPage
            ? '@page("${decl.route}")'
            : decl.params.isEmpty
                ? 'composable'
                : '(${decl.params.map((p) => p.name).join(', ')})',
        'kind': SymbolKind.$class,
        'range': document.rangeOfSpan(decl.span),
        'selectionRange': document.rangeOfSpan(decl.span),
        'children': [
          for (final val in decl.vals)
            {
              'name': val.name,
              'detail': val.expr.length > 60
                  ? '${val.expr.substring(0, 57)}...'
                  : val.expr,
              'kind': SymbolKind.variable,
              'range': document.rangeOfSpan(val.span),
              'selectionRange': document.rangeOfSpan(val.span),
            },
        ],
      },
  ];
}

/// Workspace-wide symbol search, so `@Dashboard` finds the screen.
List<Map<String, Object?>> workspaceSymbols(Workspace workspace, String query) {
  final needle = query.toLowerCase();
  final results = <Map<String, Object?>>[];

  for (final entry in workspace.composables) {
    if (needle.isNotEmpty && !entry.decl.name.toLowerCase().contains(needle)) {
      continue;
    }
    final analysis = workspace[entry.uri];
    if (analysis == null) continue;
    results.add({
      'name': entry.decl.name,
      'kind': SymbolKind.$class,
      'location': {
        'uri': entry.uri,
        'range': analysis.document.rangeOfSpan(entry.decl.span),
      },
      'containerName': entry.decl.isPage ? entry.decl.route : null,
    });
  }
  return results;
}
