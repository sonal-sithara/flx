import 'package:flxc/flxc.dart';

import 'documents.dart';

/// Tokenizes as much as possible, even when the file is mid-edit.
///
/// The lexer is strict: `Text("hi` throws on the unterminated string, which is
/// the single most common state while typing. Completion must still work
/// there, so on failure we re-tokenize the prefix that came before the
/// problem. Offsets stay valid because the prefix starts at zero.
List<Token> tokenizeTolerant(Source source) {
  try {
    return Lexer(source).tokenize();
  } on FlxError catch (error) {
    final cut = error.span?.start ?? 0;
    if (cut <= 0) return const [];
    try {
      return Lexer(Source(source.path, source.text.substring(0, cut)))
          .tokenize();
    } on FlxError {
      return const [];
    }
  }
}

/// Everything the server knows about one document at a moment in time.
class Analysis {
  Analysis({
    required this.document,
    required this.tokens,
    required this.ast,
    required this.astIsCurrent,
    required this.error,
  });

  final TextDocument document;

  /// Always present, even for a file that does not parse.
  final List<Token> tokens;

  /// The most recent parse that succeeded. May be stale — that is the point.
  /// An outline that vanishes on every keystroke is worse than a slightly old
  /// one.
  final FlxFile? ast;

  /// Whether [ast] reflects the current text.
  final bool astIsCurrent;

  /// The parse error, if the current text does not parse.
  final FlxError? error;

  bool get parses => error == null;
}

/// Parses and caches per document, and indexes composables across the
/// workspace so definitions resolve between files.
class Workspace {
  final _analyses = <String, Analysis>{};

  Analysis? operator [](String uri) => _analyses[uri];

  Iterable<Analysis> get all => _analyses.values;

  void forget(String uri) => _analyses.remove(uri);

  /// Re-analyses [document], keeping the previous AST if the new text does
  /// not parse.
  Analysis analyze(TextDocument document) {
    final source = document.source;
    final tokens = tokenizeTolerant(source);
    final previous = _analyses[document.uri];

    FlxFile? ast;
    FlxError? error;
    try {
      ast = Parser.parse(source);
    } on FlxError catch (e) {
      error = e;
    } on Object catch (e) {
      // A parser bug must degrade to "no diagnostics", never take the server
      // down mid-session.
      error = FlxError('internal parse failure: $e', null);
    }

    final analysis = Analysis(
      document: document,
      tokens: tokens,
      ast: ast ?? previous?.ast,
      astIsCurrent: ast != null,
      error: error,
    );
    _analyses[document.uri] = analysis;
    return analysis;
  }

  /// Every composable declared anywhere in the workspace, newest analysis
  /// wins. Used for go-to-definition across files.
  Iterable<({String uri, ComposableDecl decl})> get composables sync* {
    for (final entry in _analyses.entries) {
      final ast = entry.value.ast;
      if (ast == null) continue;
      for (final decl in ast.composables) {
        yield (uri: entry.key, decl: decl);
      }
    }
  }

  /// Finds a composable by name, preferring the file asking.
  ///
  /// Nothing namespaces composables, so a workspace can hold several called
  /// `Badge`. Iterating the index and taking the first match resolved by hash
  /// order — go-to-definition on a name declared in the very same file could
  /// land in an unrelated one. The local declaration wins, as it would in
  /// Dart.
  ({String uri, ComposableDecl decl})? findComposable(
    String name, {
    String? preferUri,
  }) {
    if (preferUri != null) {
      final local = _analyses[preferUri]?.ast;
      if (local != null) {
        for (final decl in local.composables) {
          if (decl.name == name) return (uri: preferUri, decl: decl);
        }
      }
    }
    for (final candidate in composables) {
      if (candidate.decl.name == name) return candidate;
    }
    return null;
  }
}

/// Converts a flxc error into the single LSP diagnostic it represents.
///
/// The parser stops at the first problem, so there is never more than one.
/// That is a real limit compared with the Dart analyzer, but one precise,
/// correctly-placed error is far more useful than a cascade of invented ones.
Map<String, Object?> diagnosticFor(TextDocument document, FlxError error) {
  final span = error.span;
  final range = span == null
      ? {'start': document.positionAt(0), 'end': document.positionAt(0)}
      : document.rangeOfSpan(span);

  final message =
      error.hint == null ? error.message : '${error.message}\n\n${error.hint}';

  return {
    'range': range,
    'severity': 1, // Error
    'source': 'flxc',
    'message': message,
  };
}
