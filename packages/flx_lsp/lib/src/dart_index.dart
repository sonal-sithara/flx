import 'dart:convert';
import 'dart:io';

import 'documents.dart';

/// A top-level Dart declaration, and where to find it.
class DartSymbol {
  const DartSymbol({
    required this.name,
    required this.uri,
    required this.line,
    required this.character,
    required this.length,
  });

  final String name;
  final String uri;
  final int line;
  final int character;
  final int length;

  /// The LSP Location a jump returns.
  Map<String, Object?> get location => {
        'uri': uri,
        'range': {
          'start': {'line': line, 'character': character},
          'end': {'line': line, 'character': character + length},
        },
      };
}

/// Where the hooks and the widgets actually live.
///
/// flxc hands expressions to Dart verbatim, so a `.flx` file is full of names
/// the flx parser never resolves: `useState` is a function in flx_runtime,
/// `Button` a class beside it, `TransactionsViewModel` one of yours. Without
/// an index of those, the editor can navigate the DSL but not the language
/// underneath it — and go-to-definition dies exactly where a reader most wants
/// it, on the hook whose contract they are trying to remember.
///
/// Nothing here parses Dart. It scans for declarations that start a line,
/// which is all a jump needs and all a regex can be trusted with. That is the
/// same trade the rest of the server makes: no analyzer to keep alive, and the
/// failure mode is a name that does not resolve rather than one that resolves
/// to the wrong place.
class DartIndex {
  final _byName = <String, List<DartSymbol>>{};

  /// Directories already walked. Packages are reachable by several paths —
  /// the workspace, a path dependency, package_config — and scanning one twice
  /// would double every result the editor shows.
  final _scanned = <String>{};

  bool get isEmpty => _byName.isEmpty;
  int get length => _byName.length;

  /// Declarations named [name], best candidate first.
  ///
  /// Order is insertion order, so it follows the order directories were
  /// indexed in: the workspace before its dependencies, which is what makes a
  /// local `Badge` win over a package's.
  List<DartSymbol> lookup(String name) => _byName[name] ?? const [];

  /// Indexes every `.dart` file under [path]. Cheap enough to do at startup —
  /// a scan of this repository is well under a tenth of a second — but it is
  /// still a walk, so it happens once per directory.
  void addDirectory(String path) {
    final directory = Directory(path);
    if (!directory.existsSync()) return;

    final resolved = directory.resolveSymbolicLinksSync();
    if (!_scanned.add(resolved)) return;

    try {
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (_isPruned(entity.path)) continue;
        addFile(entity);
      }
    } on FileSystemException {
      // A directory that disappears mid-walk costs us its symbols, nothing
      // more.
    }
  }

  void addFile(File file) {
    // Generated output is never a definition: `accounts.dart` beside
    // `accounts.flx` holds a class the user did not write, and jumping into it
    // teaches them to edit a file the next build overwrites.
    if (File('${file.path.substring(0, file.path.length - 5)}.flx')
        .existsSync()) {
      return;
    }

    final String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException {
      return;
    }
    indexSource(pathToUri(file.path), text);
  }

  /// Indexes one file's text. Separate from [addFile] so tests can index a
  /// string, and so an in-memory buffer could be indexed later.
  void indexSource(String uri, String text) {
    final lineStarts = _lineStarts(text);
    // A `'''` string holding example code puts `class Foo` at column zero
    // without declaring anything — and this file's own tests are full of them.
    // Blanking keeps every offset, so matches still map onto the real text.
    final scannable = _blankLiteralsAndComments(text);

    void record(int offset, String name) {
      final line = _lineOf(lineStarts, offset);
      _byName.putIfAbsent(name, () => []).add(
            DartSymbol(
              name: name,
              uri: uri,
              line: line,
              character: offset - lineStarts[line],
              length: name.length,
            ),
          );
    }

    for (final match in _declaration.allMatches(scannable)) {
      final name = match.group(2)!;
      if (_notAName.contains(name)) continue;
      // The pattern ends with the name, so the match's own tail locates it.
      record(match.end - name.length, name);
    }

    for (final match in _function.allMatches(scannable)) {
      final name = match.group(2)!;
      if (_notAName.contains(name)) continue;
      record(match.start + match.group(1)!.length, name);
    }
  }

  /// `class Foo`, and every modifier Dart lets precede it, plus the other
  /// declaration keywords. Anchored to the start of a line, which is what
  /// makes it top-level: a member is indented.
  static final _declaration = RegExp(
    r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
    r'(class|mixin|enum|extension\s+type|extension|typedef)\s+([A-Za-z_]\w*)',
    multiLine: true,
  );

  /// A top-level function: a return type, a name, then a parameter list.
  /// `=` is deliberately absent from the type's character class — without it,
  /// `final injector = Injector()` would index `Injector` as a declaration.
  static final _function = RegExp(
    r'^([A-Za-z_][\w<>?,\s.]*?\s)([a-zA-Z_]\w*)\s*(?:<[^>]*>)?\s*\(',
    multiLine: true,
  );

  /// Keywords that the function pattern can otherwise mistake for a name.
  static const _notAName = {
    'if', 'for', 'while', 'switch', 'catch', 'return', 'assert', 'super',
    'this', 'new', 'on', 'of', 'yield', 'await', 'else', 'do', 'get', 'set',
  };

  static const _prunedDirectories = {
    '.dart_tool',
    '.git',
    '.symlinks',
    '.vscode-test',
    'build',
    'node_modules',
  };

  static bool _isPruned(String path) {
    for (final segment in _prunedDirectories) {
      if (path.contains('/$segment/')) return true;
    }
    return false;
  }

  /// Replaces the contents of strings and comments with spaces, character for
  /// character, so offsets and line numbers still line up with the original.
  ///
  /// This is not a Dart lexer and does not need to be. It only has to stop the
  /// scan reading code that is being quoted rather than declared — which is
  /// how `useState` in a test fixture ended up as the definition of the real
  /// hook.
  static String _blankLiteralsAndComments(String text) {
    final out = StringBuffer();
    var i = 0;

    void blankTo(int end) {
      for (var j = i; j < end && j < text.length; j++) {
        // Newlines survive: `^` in the patterns is what makes a declaration
        // top-level, and losing a line break would move every one after it.
        out.write(text[j] == '\n' ? '\n' : ' ');
      }
      i = end;
    }

    while (i < text.length) {
      final char = text[i];
      final next = i + 1 < text.length ? text[i + 1] : '';

      if (char == '/' && next == '/') {
        final end = text.indexOf('\n', i);
        blankTo(end < 0 ? text.length : end);
        continue;
      }
      if (char == '/' && next == '*') {
        var depth = 0;
        var j = i;
        while (j < text.length) {
          if (text.startsWith('/*', j)) {
            depth++;
            j += 2;
          } else if (text.startsWith('*/', j)) {
            depth--;
            j += 2;
            if (depth == 0) break;
          } else {
            j++;
          }
        }
        blankTo(j);
        continue;
      }
      if (char == '"' || char == "'") {
        final raw = i > 0 && text[i - 1] == 'r';
        final triple = text.startsWith(char * 3, i);
        final quote = triple ? char * 3 : char;
        var j = i + quote.length;
        while (j < text.length) {
          if (!raw && text[j] == r'\') {
            j += 2;
            continue;
          }
          if (text.startsWith(quote, j)) {
            j += quote.length;
            break;
          }
          j++;
        }
        blankTo(j > text.length ? text.length : j);
        continue;
      }

      out.write(char);
      i++;
    }
    return out.toString();
  }

  static List<int> _lineStarts(String text) {
    final starts = <int>[0];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0a) starts.add(i + 1);
    }
    return starts;
  }

  static int _lineOf(List<int> starts, int offset) {
    var low = 0;
    var high = starts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (starts[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }
}

/// Every package the workspace resolves, as name → `lib/` directory.
///
/// Read from `.dart_tool/package_config.json`, which is the only place that
/// knows where `package:flx_runtime` landed — it is a path dependency in this
/// repository, a pub package in someone else's checkout, and a `.symlinks`
/// entry inside a Flutter app. Editing `apps/ledger` alone still finds the
/// hooks this way, even though flx_runtime sits outside that folder.
Map<String, String> resolvedPackages(String root) {
  final packages = <String, String>{};
  final directory = Directory(root);
  if (!directory.existsSync()) return packages;

  final configs = <File>[];
  final top = File('$root/.dart_tool/package_config.json');
  if (top.existsSync()) configs.add(top);
  try {
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart_tool/package_config.json')) continue;
      if (entity.path != top.path) configs.add(entity);
    }
  } on FileSystemException {
    // Fall through with whatever was found.
  }

  for (final config in configs) {
    try {
      final decoded = jsonDecode(config.readAsStringSync());
      if (decoded is! Map) continue;
      final entries = decoded['packages'];
      if (entries is! List) continue;

      final base = Uri.file(config.path);
      for (final entry in entries) {
        if (entry is! Map) continue;
        final name = entry['name'];
        var rootUri = entry['rootUri'];
        if (name is! String || rootUri is! String) continue;
        // Without the trailing slash the last segment is a file name to
        // Uri.resolve, and `packages/flx_runtime` + `lib/` becomes
        // `packages/lib/`.
        if (!rootUri.endsWith('/')) rootUri = '$rootUri/';
        final packageUri = entry['packageUri'];
        final lib = base
            .resolve(rootUri)
            .resolve(packageUri is String ? packageUri : 'lib/');
        packages.putIfAbsent(name, () => lib.toFilePath());
      }
    } on Object {
      // A half-written package_config during a `pub get` is not worth a
      // crashed request.
    }
  }
  return packages;
}
