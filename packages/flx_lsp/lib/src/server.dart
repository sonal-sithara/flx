import 'dart:async';
import 'dart:io';

import 'package:flx_compiler/flx_compiler.dart';

import 'analysis.dart';
import 'completion.dart';
import 'dart_index.dart';
import 'documents.dart';
import 'features.dart';
import 'protocol.dart';
import 'semantics.dart';

/// The flx language server.
///
/// Everything it answers is derived from flxc: the same lexer, parser and
/// spans that produce compile errors also drive completion, hover and
/// navigation, so the editor can never disagree with the build.
class FlxLanguageServer {
  FlxLanguageServer(this.connection);

  final LspConnection connection;
  final documents = DocumentStore();
  final workspace = Workspace();

  /// Top-level Dart declarations, for jumping to hooks, widgets and the app's
  /// own classes.
  final dartIndex = DartIndex();

  /// Workspace roots, kept so dependencies can be indexed later.
  final _roots = <String>[];

  /// How far the Dart index has been widened: 0 the workspace, 1 Flutter as
  /// well, 2 every package the workspace resolves.
  int _indexReach = 0;

  bool _initialized = false;
  bool _shutdownRequested = false;

  /// Syntax errors from flxc, republished immediately on every change.
  final _syntax = <String, List<Map<String, Object?>>>{};

  /// Type errors from Dart, refreshed on save. Kept separate so a keystroke
  /// does not wipe them and a save does not wipe the syntax ones.
  final _semantic = <String, List<Map<String, Object?>>>{};

  SemanticDiagnostics? _semantics;

  /// Set by the `exit` notification, so a host can await a clean stop.
  final _exited = <void Function(int code)>[];

  void onExit(void Function(int code) handler) => _exited.add(handler);

  Future<void> serve() async {
    connection.listen();
    await for (final message in connection.messages) {
      try {
        _handle(message);
      } on Object catch (error, stack) {
        // A bad request must never take the session down: the editor would
        // silently lose all language features until it is restarted.
        final id = message['id'];
        if (id != null) {
          connection.respondError(
            id,
            LspErrorCode.internalError,
            '$error',
          );
        }
        stderr.writeln('flx_lsp: $error\n$stack');
      }
    }
  }

  void _handle(Map<String, Object?> message) {
    final method = message['method'] as String?;
    if (method == null) return; // a response to something we sent
    final id = message['id'];
    final params = (message['params'] as Map<String, Object?>?) ?? const {};

    if (!_initialized && method != 'initialize' && method != 'exit') {
      if (id != null) {
        connection.respondError(
          id,
          LspErrorCode.serverNotInitialized,
          'server not initialized',
        );
      }
      return;
    }

    switch (method) {
      case 'initialize':
        _initialized = true;
        _configure(params);
        _indexWorkspace(params);
        connection.respond(id!, _capabilities());
      case 'initialized':
        break;
      case 'shutdown':
        _shutdownRequested = true;
        connection.respond(id!, null);
      case 'exit':
        for (final handler in _exited) {
          handler(_shutdownRequested ? 0 : 1);
        }
      case 'textDocument/didOpen':
        _didOpen(params);
      case 'textDocument/didChange':
        _didChange(params);
      case 'textDocument/didSave':
        _refresh(_uriOf(params));
        _refreshSemantics(_uriOf(params));
      case 'textDocument/didClose':
        _didClose(params);
      case 'textDocument/completion':
        connection.respond(id!, _completion(params));
      case 'textDocument/hover':
        connection.respond(id!, _hover(params));
      case 'textDocument/definition':
        connection.respond(id!, _definition(params));
      case 'textDocument/documentSymbol':
        connection.respond(id!, _documentSymbol(params));
      case 'workspace/symbol':
        connection.respond(
          id!,
          workspaceSymbols(workspace, params['query'] as String? ?? ''),
        );
      default:
        if (id != null) {
          connection.respondError(
            id,
            LspErrorCode.methodNotFound,
            'unhandled method: $method',
          );
        }
    }
  }

  Map<String, Object?> _capabilities() => {
        'capabilities': {
          'textDocumentSync': {
            'openClose': true,
            'change': 2, // incremental
          },
          'completionProvider': {
            // `.` for enum shorthands, `:` after an argument name, `(` and `,`
            // for argument lists, `@` for annotations.
            'triggerCharacters': ['.', ':', '(', ',', '@'],
          },
          'hoverProvider': true,
          'definitionProvider': true,
          'documentSymbolProvider': true,
          'workspaceSymbolProvider': true,
        },
        'serverInfo': {'name': 'flx_lsp', 'version': '0.3.0'},
      };

  /// Reads initializationOptions.
  ///
  /// `semanticDiagnostics: false` turns off the analyzer pass for anyone who
  /// would rather the editor never wrote generated files.
  void _configure(Map<String, Object?> params) {
    final options = params['initializationOptions'];
    final enabled = !(options is Map && options['semanticDiagnostics'] == false);

    _semantics = SemanticDiagnostics(
      enabled: enabled,
      onLog: (message) => connection.notify('window/logMessage', {
        'type': 3,
        'message': message,
      }),
      publish: _publishSemantic,
    );
  }

  void _refreshSemantics(String uri) {
    final document = documents[uri];
    final semantics = _semantics;
    if (document == null || semantics == null) return;
    unawaited(semantics.refresh(document.path));
  }

  /// Called back once the analyzer finishes for one `.flx`.
  void _publishSemantic(String flxPath, List<MappedDiagnostic> diagnostics) {
    final uri = pathToUri(flxPath);
    final document = documents[uri];
    if (document == null) return;

    _semantic[uri] = [
      for (final diagnostic in diagnostics)
        lspDiagnosticFor(document, diagnostic),
    ];
    _publishMerged(uri);
  }

  /// Parses every `.flx` under the workspace root, so go-to-definition and
  /// workspace symbols work for files the editor has never opened.
  void _indexWorkspace(Map<String, Object?> params) {
    final roots = <String>[];
    final folders = params['workspaceFolders'];
    if (folders is List) {
      for (final folder in folders) {
        if (folder is Map && folder['uri'] is String) {
          roots.add(uriToPath(folder['uri']! as String));
        }
      }
    }
    final rootUri = params['rootUri'];
    if (roots.isEmpty && rootUri is String) roots.add(uriToPath(rootUri));

    _roots
      ..clear()
      ..addAll(roots);

    for (final root in roots) {
      final directory = Directory(root);
      if (!directory.existsSync()) continue;
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.flx')) continue;
        try {
          final uri = pathToUri(entity.path);
          final document =
              documents.open(uri, entity.readAsStringSync(), 0);
          workspace.analyze(document);
        } on FileSystemException {
          // Unreadable file — skip it rather than abandoning the whole index.
        }
      }
      dartIndex.addDirectory(root);
    }

    // flx_runtime holds every hook and every widget the DSL offers, and it is
    // routinely outside the folder being edited — `apps/ledger` is its own
    // root. Resolving it now, rather than with the rest of the dependencies,
    // keeps the most common jump off the slow path.
    for (final root in roots) {
      final runtime = resolvedPackages(root)['flx_runtime'];
      if (runtime != null) dartIndex.addDirectory(runtime);
    }
  }

  /// Widens the Dart index by one step, and reports whether there was one.
  ///
  /// Deferred because it is the expensive half — Flutter is 20MB of Dart, and
  /// the rest of a Flutter app's packages another 40 — and a session that
  /// never jumps into a package should never pay for it. In two steps because
  /// the framework answers almost every miss: `Text` costs half a second,
  /// and only a name that is in neither the workspace nor Flutter pays for
  /// the long tail of transitive packages.
  bool _widenIndex() {
    if (_indexReach >= 2) return false;
    _indexReach++;

    for (final root in _roots) {
      final packages = resolvedPackages(root);
      if (_indexReach == 1) {
        final flutter = packages['flutter'];
        if (flutter != null) dartIndex.addDirectory(flutter);
      } else {
        for (final lib in packages.values) {
          dartIndex.addDirectory(lib);
        }
      }
    }
    return true;
  }

  // ------------------------------------------------------------- lifecycle

  void _didOpen(Map<String, Object?> params) {
    final item = params['textDocument'] as Map<String, Object?>;
    final uri = item['uri']! as String;
    final document = documents.open(
      uri,
      item['text'] as String? ?? '',
      item['version'] as int? ?? 0,
    );
    _publish(workspace.analyze(document));
  }

  void _didChange(Map<String, Object?> params) {
    final item = params['textDocument'] as Map<String, Object?>;
    final uri = item['uri']! as String;
    final document = documents[uri];
    if (document == null) return;

    final changes = params['contentChanges'];
    if (changes is List) {
      for (final change in changes) {
        if (change is! Map<String, Object?>) continue;
        document.applyChange(
          change['range'] as Map<String, Object?>?,
          change['text'] as String? ?? '',
        );
      }
    }
    final version = item['version'];
    if (version is int) document.version = version;

    _publish(workspace.analyze(document));
  }

  void _didClose(Map<String, Object?> params) {
    final uri = _uriOf(params);
    // Diagnostics are cleared, but the analysis stays in the index so other
    // files can still resolve composables declared here.
    _syntax.remove(uri);
    _semantic.remove(uri);
    connection.notify('textDocument/publishDiagnostics', {
      'uri': uri,
      'diagnostics': const [],
    });
    documents.close(uri);
  }

  void _refresh(String uri) {
    final document = documents[uri];
    if (document == null) return;
    _publish(workspace.analyze(document));
  }

  void _publish(Analysis analysis) {
    final error = analysis.error;
    final uri = analysis.document.uri;
    _syntax[uri] = [
      if (error != null) diagnosticFor(analysis.document, error),
    ];
    // A file that no longer parses cannot have meaningful type errors, and
    // stale ones would sit at positions that have since moved.
    if (error != null) _semantic.remove(uri);
    _publishMerged(uri);
  }

  void _publishMerged(String uri) {
    connection.notify('textDocument/publishDiagnostics', {
      'uri': uri,
      if (documents[uri] != null) 'version': documents[uri]!.version,
      'diagnostics': [
        ...?_syntax[uri],
        ...?_semantic[uri],
      ],
    });
  }

  // -------------------------------------------------------------- features

  Object? _completion(Map<String, Object?> params) {
    final resolved = _resolve(params);
    if (resolved == null) return const <Map<String, Object?>>[];
    return {
      'isIncomplete': false,
      'items': completionsAt(workspace, resolved.analysis, resolved.offset),
    };
  }

  Object? _hover(Map<String, Object?> params) {
    final resolved = _resolve(params);
    if (resolved == null) return null;
    return hoverAt(workspace, resolved.analysis, resolved.offset);
  }

  Object _definition(Map<String, Object?> params) {
    final resolved = _resolve(params);
    if (resolved == null) return const <Map<String, Object?>>[];

    // Each miss widens the search: the workspace, then Flutter, then every
    // package. A name that is in none of them costs the full scan once.
    while (true) {
      final locations = definitionAt(
        workspace,
        resolved.analysis,
        resolved.offset,
        dartIndex: dartIndex,
      );
      if (locations.isNotEmpty) return locations;
      if (!_widenIndex()) return locations;
    }
  }

  Object _documentSymbol(Map<String, Object?> params) {
    final analysis = workspace[_uriOf(params)];
    if (analysis == null) return const <Map<String, Object?>>[];
    return documentSymbols(analysis);
  }

  ({Analysis analysis, int offset})? _resolve(Map<String, Object?> params) {
    final uri = _uriOf(params);
    final document = documents[uri];
    final analysis = workspace[uri];
    if (document == null || analysis == null) return null;

    final position = params['position'];
    if (position is! Map<String, Object?>) return null;
    return (analysis: analysis, offset: document.offsetAt(position));
  }

  static String _uriOf(Map<String, Object?> params) {
    final item = params['textDocument'];
    if (item is Map && item['uri'] is String) return item['uri']! as String;
    return '';
  }
}
