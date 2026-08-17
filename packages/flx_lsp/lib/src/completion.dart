import 'package:flxc/src/token.dart';

import 'analysis.dart';
import 'catalog.dart';
import 'documents.dart';

/// LSP CompletionItemKind values, named.
abstract final class ItemKind {
  static const function = 3;
  static const variable = 6;
  static const $class = 7;
  static const property = 10;
  static const keyword = 14;
  static const snippet = 15;
  static const enumMember = 20;
}

enum ContextKind {
  /// Outside any composable: imports, @page, composable.
  topLevel,

  /// After `val x =` — hooks belong here.
  valExpression,

  /// Where a child widget can start.
  widgetPosition,

  /// Just after `(` or `,` in an argument list.
  argumentName,

  /// After `argName:` or `argName: .` — enum shorthands.
  shorthandValue,

  /// Inside an expression: locals, then widgets for widget-valued arguments.
  expression,

  /// Inside a string or comment: offer nothing.
  none,
}

class CompletionContext {
  const CompletionContext(
    this.kind, {
    this.widget,
    this.argument,
    this.locals = const [],
  });

  final ContextKind kind;

  /// The widget whose argument list the cursor sits in.
  final String? widget;

  /// The argument name the cursor is providing a value for.
  final String? argument;

  /// `val` names and parameters visible at the cursor.
  final List<String> locals;
}

/// Works out what the cursor is looking at, using only the token stream.
///
/// Deliberately parse-free: a file being typed into almost never parses, and
/// completion that only works on valid files is completion that never works.
CompletionContext contextAt(Analysis analysis, int offset) {
  final document = analysis.document;

  final tokens = analysis.tokens
      .where((t) => !t.isEof && t.span.end <= offset)
      .toList();

  // A completed string literal swallows the cursor, so it never appears in
  // the list above. `"total: ${cou|}"` is code, not prose — offer locals
  // there. Member completion (`vm.`) would need Dart type information the
  // server does not have, so it stays out.
  final enclosing = _tokenContaining(analysis, offset);
  if (enclosing != null && enclosing.type == TokenType.string) {
    return _insideInterpolation(enclosing, offset)
        ? CompletionContext(
            ContextKind.expression,
            locals: _localsBefore(tokens),
          )
        : const CompletionContext(ContextKind.none);
  }

  // Unterminated strings and comments produce no token at all, so they are
  // detected from the raw line instead.
  if (_insideStringOrComment(document, offset)) {
    return const CompletionContext(ContextKind.none);
  }

  if (tokens.isEmpty) return const CompletionContext(ContextKind.topLevel);

  final previous = tokens.last;
  final locals = _localsBefore(tokens);

  // `style: .` / `style:` — an enum shorthand value.
  final shorthand = _shorthandArgument(tokens);
  if (shorthand != null) {
    return CompletionContext(
      ContextKind.shorthandValue,
      argument: shorthand,
      locals: locals,
    );
  }

  // `@` opens an annotation.
  if (previous.lexeme == '@') {
    return CompletionContext(ContextKind.topLevel, locals: locals);
  }

  final open = _innermostOpenParen(tokens);
  if (open != null) {
    final widget = open.index > 0 &&
            tokens[open.index - 1].type == TokenType.identifier
        ? tokens[open.index - 1].lexeme
        : null;

    // Right after `(` or `,` the cursor is naming an argument.
    if (previous.lexeme == '(' || previous.lexeme == ',') {
      return CompletionContext(
        ContextKind.argumentName,
        widget: widget,
        locals: locals,
      );
    }
    return CompletionContext(
      ContextKind.expression,
      widget: widget,
      locals: locals,
    );
  }

  // `val name = ` — the right-hand side is where hooks go.
  if (_isValInitialiser(tokens)) {
    return CompletionContext(ContextKind.valExpression, locals: locals);
  }

  final depth = _braceDepth(tokens);
  if (depth <= 0) {
    return CompletionContext(ContextKind.topLevel, locals: locals);
  }
  return CompletionContext(ContextKind.widgetPosition, locals: locals);
}

/// Builds the completion list for a cursor position.
List<Map<String, Object?>> completionsAt(
  Workspace workspace,
  Analysis analysis,
  int offset,
) {
  final context = contextAt(analysis, offset);

  return switch (context.kind) {
    ContextKind.none => const [],
    ContextKind.topLevel => [
        for (final keyword in keywords)
          if (const {'composable', 'import', 'page'}.contains(keyword.name))
            _item(keyword),
      ],
    ContextKind.valExpression => [
        for (final hook in hooks) _item(hook, sortGroup: '0'),
        for (final local in context.locals) _local(local),
      ],
    ContextKind.widgetPosition => [
        for (final widget in allWidgets) _item(widget, sortGroup: '0'),
        for (final keyword in keywords)
          if (const {'if', 'for', 'val'}.contains(keyword.name))
            _item(keyword, sortGroup: '1'),
        ..._composableItems(workspace, analysis),
      ],
    ContextKind.argumentName => _argumentNames(context.widget),
    ContextKind.shorthandValue => _shorthandValues(context.argument!),
    ContextKind.expression => [
        for (final local in context.locals) _local(local),
        ..._composableItems(workspace, analysis, sortGroup: '1'),
        for (final widget in allWidgets) _item(widget, sortGroup: '2'),
      ],
  };
}

// --------------------------------------------------------------- item build

Map<String, Object?> _item(FlxSymbol symbol, {String sortGroup = '0'}) => {
      'label': symbol.name,
      'kind': switch (symbol.kind) {
        FlxKind.hook => ItemKind.function,
        FlxKind.keyword => ItemKind.keyword,
        FlxKind.modifier || FlxKind.shorthand => ItemKind.property,
        _ => ItemKind.$class,
      },
      'detail': symbol.signature,
      'documentation': {'kind': 'markdown', 'value': symbol.documentation},
      'insertText': symbol.insertText,
      'insertTextFormat': symbol.snippet == null ? 1 : 2,
      'sortText': '$sortGroup${symbol.name}',
    };

Map<String, Object?> _local(String name) => {
      'label': name,
      'kind': ItemKind.variable,
      'detail': 'local',
      'sortText': '0$name',
    };

/// Composables offered as widgets.
///
/// Names come from the **token stream** for the file being edited, because the
/// block you are about to type into is empty and therefore unparseable — the
/// AST is missing at exactly the moment you need this. Other files contribute
/// through the workspace index, where a successful parse is available.
List<Map<String, Object?>> _composableItems(
  Workspace workspace,
  Analysis analysis, {
  String sortGroup = '0',
}) {
  final items = <Map<String, Object?>>[];
  final seen = <String>{};

  for (final name in _composableNames(analysis.tokens)) {
    if (!seen.add(name)) continue;
    items.add({
      'label': name,
      'kind': ItemKind.$class,
      'detail': 'composable $name',
      'sortText': '$sortGroup$name',
    });
  }

  for (final entry in workspace.composables) {
    final decl = entry.decl;
    if (!seen.add(decl.name)) continue;
    items.add({
      'label': decl.name,
      'kind': ItemKind.$class,
      'detail': decl.params.isEmpty
          ? 'composable ${decl.name}'
          : 'composable ${decl.name}(${decl.params.map((p) => p.name).join(', ')})',
      'documentation': {
        'kind': 'markdown',
        'value': decl.isPage
            ? 'A screen, routed at `${decl.route}`.'
            : 'A composable in this workspace.',
      },
      'insertText': decl.params.isEmpty
          ? decl.name
          : '${decl.name}(${[
              for (var i = 0; i < decl.params.length; i++)
                '${decl.params[i].name}: \${${i + 1}:${decl.params[i].name}}',
            ].join(', ')})',
      'insertTextFormat': decl.params.isEmpty ? 1 : 2,
      'sortText': '$sortGroup${decl.name}',
    });
  }
  return items;
}

/// `composable Name` occurrences in a token stream.
Iterable<String> _composableNames(List<Token> tokens) sync* {
  for (var i = 0; i < tokens.length - 1; i++) {
    if (tokens[i].isIdent('composable') &&
        tokens[i + 1].type == TokenType.identifier) {
      yield tokens[i + 1].lexeme;
    }
  }
}

List<Map<String, Object?>> _argumentNames(String? widget) {
  final items = <Map<String, Object?>>[];
  final seen = <String>{};

  void add(String name, String documentation, String group) {
    if (!seen.add(name)) return;
    items.add({
      'label': name,
      'kind': ItemKind.property,
      'detail': 'argument',
      'documentation': {'kind': 'markdown', 'value': documentation},
      'insertText': '$name: ',
      'sortText': '$group$name',
    });
  }

  if (widget != null) {
    for (final name in widgetArguments[widget] ?? const <String>[]) {
      add(name, 'Argument of `$widget`.', '0');
    }
    if (const {'Column', 'Row', 'Stack', 'Wrap'}.contains(widget)) {
      layoutArguments.forEach((name, doc) => add(name, doc, '0'));
    }
  }
  modifierArguments.forEach((name, doc) => add(name, doc, '1'));
  return items;
}

List<Map<String, Object?>> _shorthandValues(String argument) {
  // Any `*Icon` argument resolves against Icons.
  if (argument == 'icon' || argument.endsWith('Icon')) {
    return [
      for (final icon in commonIcons)
        {
          'label': '.$icon',
          'kind': ItemKind.enumMember,
          'detail': 'Icons.$icon',
          'insertText': icon,
          'sortText': '0$icon',
        },
    ];
  }

  final entry = shorthandValues[argument];
  if (entry == null) return const [];
  final (type, members) = entry;
  return [
    for (final member in members)
      {
        'label': '.$member',
        'kind': ItemKind.enumMember,
        'detail': '$type.$member',
        'insertText': member,
        'sortText': '0$member',
      },
  ];
}

// ------------------------------------------------------------ token walking

/// The token strictly containing [offset], if any.
Token? _tokenContaining(Analysis analysis, int offset) {
  for (final token in analysis.tokens) {
    if (token.isEof) continue;
    if (offset > token.span.start && offset < token.span.end) return token;
  }
  return null;
}

/// Whether [offset] falls inside a `${ ... }` region of a string token.
bool _insideInterpolation(Token string, int offset) {
  final local = offset - string.span.start;
  final text = string.lexeme;

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
    // j is one past the closing brace, or the end of an unclosed one.
    if (local > i + 1 && local < j) return true;
    i = j - 1;
  }
  return false;
}

/// `argName:` or `argName: .` immediately before the cursor.
String? _shorthandArgument(List<Token> tokens) {
  bool isShorthandArg(String name) =>
      shorthandValues.containsKey(name) ||
      name == 'icon' ||
      name.endsWith('Icon');

  final last = tokens.last;
  if (last.lexeme == '.' && tokens.length >= 3) {
    final colon = tokens[tokens.length - 2];
    final name = tokens[tokens.length - 3];
    if (colon.lexeme == ':' &&
        name.type == TokenType.identifier &&
        isShorthandArg(name.lexeme)) {
      return name.lexeme;
    }
  }
  if (last.lexeme == ':' && tokens.length >= 2) {
    final name = tokens[tokens.length - 2];
    if (name.type == TokenType.identifier && isShorthandArg(name.lexeme)) {
      return name.lexeme;
    }
  }
  return null;
}

/// The innermost `(` that is still open at the cursor.
({int index})? _innermostOpenParen(List<Token> tokens) {
  final stack = <int>[];
  for (var i = 0; i < tokens.length; i++) {
    final lexeme = tokens[i].lexeme;
    if (lexeme == '(') stack.add(i);
    if (lexeme == ')' && stack.isNotEmpty) stack.removeLast();
    // A block boundary closes any argument list that was left open by a
    // half-typed line above it.
    if (lexeme == '{' || lexeme == '}') stack.clear();
  }
  return stack.isEmpty ? null : (index: stack.last);
}

bool _isValInitialiser(List<Token> tokens) {
  // Walk back to the nearest `val`, stopping at anything that ends a binding.
  for (var i = tokens.length - 1; i >= 0; i--) {
    final lexeme = tokens[i].lexeme;
    if (lexeme == '{' || lexeme == '}') return false;
    if (tokens[i].isIdent('val')) {
      // `val name =` puts us on the right-hand side.
      return tokens.length > i + 2 && tokens[i + 2].lexeme == '=';
    }
  }
  return false;
}

int _braceDepth(List<Token> tokens) {
  var depth = 0;
  for (final token in tokens) {
    if (token.lexeme == '{') depth++;
    if (token.lexeme == '}') depth--;
  }
  return depth;
}

/// `val` names and composable parameters declared before the cursor, within
/// the enclosing composable.
List<String> _localsBefore(List<Token> tokens) {
  var start = 0;
  for (var i = tokens.length - 1; i >= 0; i--) {
    if (tokens[i].isIdent('composable')) {
      start = i;
      break;
    }
  }

  final locals = <String>[];
  // Parameters: composable Name(a, b: T)
  if (start + 2 < tokens.length && tokens[start + 2].lexeme == '(') {
    for (var i = start + 3; i < tokens.length; i++) {
      if (tokens[i].lexeme == ')') break;
      if (tokens[i].type == TokenType.identifier &&
          (tokens[i - 1].lexeme == '(' || tokens[i - 1].lexeme == ',')) {
        locals.add(tokens[i].lexeme);
      }
    }
  }

  for (var i = start; i < tokens.length - 1; i++) {
    if (tokens[i].isIdent('val') &&
        tokens[i + 1].type == TokenType.identifier) {
      locals.add(tokens[i + 1].lexeme);
    }
  }
  return locals;
}

/// True when [offset] sits inside a string literal or a comment.
///
/// Checked against the raw line rather than the token stream, because the
/// tolerant tokenizer truncates at exactly the unterminated string this needs
/// to detect.
bool _insideStringOrComment(TextDocument document, int offset) {
  final position = document.positionAt(offset);
  final line = document.lineAt(position['line']! as int);
  final column = (position['character']! as int).clamp(0, line.length);
  final before = line.substring(0, column);

  var quote = '';
  var interpolationDepth = 0;
  for (var i = 0; i < before.length; i++) {
    final char = before[i];
    if (quote.isEmpty && char == '/' && i + 1 < before.length && before[i + 1] == '/') {
      return true;
    }
    if (char == r'\') {
      i++;
      continue;
    }
    if (quote.isEmpty && (char == '"' || char == "'")) {
      quote = char;
      continue;
    }
    if (quote.isNotEmpty) {
      // `${` re-opens code inside a string, where completion is welcome.
      if (char == r'$' && i + 1 < before.length && before[i + 1] == '{') {
        interpolationDepth++;
        i++;
        continue;
      }
      if (interpolationDepth > 0 && char == '}') {
        interpolationDepth--;
        continue;
      }
      if (interpolationDepth == 0 && char == quote) quote = '';
    }
  }
  return quote.isNotEmpty && interpolationDepth == 0;
}
