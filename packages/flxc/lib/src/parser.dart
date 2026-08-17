import 'ast.dart';
import 'diagnostics.dart';
import 'lexer.dart';
import 'serializer.dart';
import 'source.dart';
import 'token.dart';

/// Layout widgets take a `{ ... }` block of children. Every other widget
/// treats a trailing block as a callback body. Keying this off the widget
/// name is what makes the grammar unambiguous without type information.
const layoutWidgets = <String, String>{
  'Column': 'column',
  'Row': 'row',
  'Stack': 'stack',
  'Wrap': 'wrap',
};

/// Recursive-descent parser for `.flx`.
class Parser {
  Parser(this.source) : _tokens = Lexer(source).tokenize();

  final Source source;
  final List<Token> _tokens;
  int _pos = 0;

  static FlxFile parse(Source source) => Parser(source)._parseFile();

  // ---------------------------------------------------------------- helpers

  Token get _current => _tokens[_pos];
  Token _peek([int offset = 0]) =>
      _tokens[(_pos + offset).clamp(0, _tokens.length - 1)];
  Token _advance() => _tokens[_pos++];

  bool _check(String lexeme) => _current.lexeme == lexeme && !_current.isEof;

  bool _match(String lexeme) {
    if (!_check(lexeme)) return false;
    _pos++;
    return true;
  }

  Token _expect(String lexeme, {String? context, String? hint}) {
    if (_check(lexeme)) return _advance();
    final where = context == null ? '' : ' $context';
    throw FlxError(
      "expected '$lexeme'$where but found ${_current.describe}",
      _current.span,
      hint: hint,
    );
  }

  Token _expectIdentifier(String what, {String? hint}) {
    if (_current.type == TokenType.identifier) return _advance();
    throw FlxError(
      'expected $what but found ${_current.describe}',
      _current.span,
      hint: hint,
    );
  }

  Span _spanFrom(Token start) =>
      Span(source, start.span.start, _tokens[_pos - 1].span.end);

  // ------------------------------------------------------------------ file

  FlxFile _parseFile() {
    final imports = <ImportDecl>[];
    while (_current.isIdent('import')) {
      final kw = _advance();
      if (_current.type != TokenType.string) {
        throw FlxError(
          'expected a quoted path after `import` but found '
          '${_current.describe}',
          _current.span,
          hint: 'write it as: import "../data/user_repository.dart"',
        );
      }
      final uri = _advance();
      imports.add(ImportDecl(uri.lexeme, _spanFrom(kw)));
    }

    final composables = <ComposableDecl>[];
    while (!_current.isEof) {
      composables.add(_parseComposable());
    }

    if (composables.isEmpty) {
      throw FlxError(
        'this file declares no composables',
        Span(source, 0, source.text.isEmpty ? 0 : 1),
        hint: 'add one, e.g.  composable Greeting { Text("hi") }',
      );
    }
    return FlxFile(
      source: source,
      imports: imports,
      composables: composables,
    );
  }

  ComposableDecl _parseComposable() {
    final start = _current;
    String? route;

    while (_check('@')) {
      _advance();
      final name = _expectIdentifier('an annotation name');
      _expect('(', context: 'after @${name.lexeme}');
      if (_current.type != TokenType.string) {
        throw FlxError(
          'expected a quoted route but found ${_current.describe}',
          _current.span,
          hint: 'write it as: @page("/settings")',
        );
      }
      final arg = _advance();
      _expect(')', context: 'to close @${name.lexeme}(...)');

      if (name.lexeme != 'page') {
        throw FlxError(
          "unknown annotation '@${name.lexeme}'",
          name.span,
          hint: "the only supported annotation is @page(\"/route\")",
        );
      }
      route = arg.lexeme.substring(1, arg.lexeme.length - 1);
      if (!route.startsWith('/')) {
        throw FlxError(
          "route '$route' must start with '/'",
          arg.span,
          hint: 'write it as: @page("/$route")',
        );
      }
    }

    if (!_current.isIdent('composable')) {
      throw FlxError(
        'expected `composable` but found ${_current.describe}',
        _current.span,
        hint: route != null
            ? '@page(...) must be followed by a composable declaration'
            : 'top-level declarations look like: composable Name { ... }',
      );
    }
    _advance();

    final nameTok = _expectIdentifier('a composable name');
    final name = nameTok.lexeme;
    if (name[0].toLowerCase() == name[0]) {
      throw FlxError(
        "composable '$name' must start with a capital letter",
        nameTok.span,
        hint: 'it becomes a Dart class, so name it '
            "'${name[0].toUpperCase()}${name.substring(1)}'",
      );
    }

    final params = _check('(') ? _parseParams() : <Param>[];
    _validateRouteParams(route, params, nameTok.span);

    _expect('{', context: 'to open the body of $name');

    final vals = <ValDecl>[];
    while (_current.isIdent('val')) {
      vals.add(_parseVal());
    }

    if (_check('}')) {
      throw FlxError(
        "composable '$name' has no widget to render",
        _current.span,
        hint: 'add a root widget, e.g.  Text("hello")',
      );
    }

    final root = _parseChild();

    // A second root widget is the single most likely mistake here, so name it.
    if (!_check('}')) {
      if (_current.isIdent('val')) {
        throw FlxError(
          '`val` declarations must come before the widget tree',
          _current.span,
          hint: 'move this val above the root widget of $name',
        );
      }
      throw FlxError(
        "composable '$name' has more than one root widget",
        _current.span,
        hint: 'wrap them in a single Column { ... } or Row { ... }',
      );
    }
    _expect('}', context: 'to close $name');

    return ComposableDecl(
      name: name,
      params: params,
      vals: vals,
      root: root,
      route: route,
      span: _spanFrom(start),
    );
  }

  void _validateRouteParams(String? route, List<Param> params, Span span) {
    if (route == null) return;
    final declared = params.map((p) => p.name).toSet();
    for (final rp in routeParamsOf(route)) {
      if (!declared.contains(rp)) {
        throw FlxError(
          "route '$route' captures ':$rp' but the composable has no "
          "'$rp' parameter",
          span,
          hint: 'add it to the signature: composable Name($rp)',
        );
      }
      final p = params.firstWhere((p) => p.name == rp);
      if (!p.isRoutable) {
        throw FlxError(
          "route parameter '$rp' must be a String, but is declared as "
          "'${p.type}'",
          p.span,
          hint: 'URL segments arrive as text — parse it inside the body '
              'instead: val ${rp}Value = int.parse($rp)',
        );
      }
    }
  }

  List<Param> _parseParams() {
    _expect('(');
    final params = <Param>[];
    while (!_check(')')) {
      final nameTok = _expectIdentifier('a parameter name');
      var type = 'String';
      if (_match(':')) {
        type = serialize(_captureType());
      }
      String? defaultValue;
      if (_match('=')) {
        defaultValue = serialize(_captureUntil(const {',', ')'}));
      }
      params.add(
        Param(nameTok.lexeme, type, _spanFrom(nameTok),
            defaultValue: defaultValue),
      );
      if (!_match(',') && !_check(')')) {
        throw FlxError(
          "expected ',' or ')' in the parameter list but found "
          '${_current.describe}',
          _current.span,
        );
      }
    }
    _expect(')', context: 'to close the parameter list');
    return params;
  }

  /// Captures a type annotation: `int`, `List<Todo>`, `String?`.
  List<Token> _captureType() {
    final out = <Token>[];
    var depth = 0;
    while (!_current.isEof) {
      final lex = _current.lexeme;
      if (depth == 0 && (lex == ',' || lex == ')' || lex == '=')) break;
      if (lex == '<') depth++;
      if (lex == '>') depth--;
      out.add(_advance());
    }
    if (out.isEmpty) {
      throw FlxError('expected a type', _current.span);
    }
    return out;
  }

  ValDecl _parseVal() {
    final kw = _advance(); // `val`
    final nameTok = _expectIdentifier(
      'a name after `val`',
      hint: 'declarations look like:  val count = useState(0)',
    );
    _expect('=',
        context: 'after `val ${nameTok.lexeme}`',
        hint: 'flx vals are always initialised: '
            'val ${nameTok.lexeme} = useState(0)');
    final tokens = _captureExpression();
    if (tokens.isEmpty) {
      throw FlxError(
        'expected an expression after `=`',
        _current.span,
        hint: 'e.g.  val ${nameTok.lexeme} = useState(0)',
      );
    }
    final references = {
      for (final t in tokens)
        if (t.type == TokenType.identifier) t.lexeme,
    };
    return ValDecl(
      nameTok.lexeme,
      serialize(tokens),
      _spanFrom(kw),
      references,
    );
  }

  /// Captures a `val` right-hand side.
  ///
  /// A val ends at the start of the next `val`, or at the root widget. The
  /// widget tree always begins with a capitalised identifier at the start of
  /// a line, which is the boundary we look for.
  List<Token> _captureExpression() {
    final out = <Token>[];
    var depth = 0;
    while (!_current.isEof) {
      final lex = _current.lexeme;
      if (depth == 0) {
        if (lex == '}') break;
        if (_current.isIdent('val')) break;
        // A capitalised identifier at depth 0 that is not a continuation
        // (`.`/`(` before it) starts the widget tree.
        if (out.isNotEmpty &&
            _current.type == TokenType.identifier &&
            _startsWidget(_current) &&
            !_isContinuation(out.last)) {
          break;
        }
      }
      if (lex == '(' || lex == '[' || lex == '{') depth++;
      if (lex == ')' || lex == ']' || lex == '}') depth--;
      out.add(_advance());
    }
    return out;
  }

  static bool _startsWidget(Token t) {
    final c = t.lexeme[0];
    return c.toUpperCase() == c && c.toLowerCase() != c;
  }

  /// True when [t] means the expression is mid-flight and the next token
  /// cannot be the start of the widget tree.
  static bool _isContinuation(Token t) => const {
        '.', '?.', '(', '[', ',', '=', '+', '-', '*', '/', '??', '=>',
        '&&', '||', '==', '!=', '<', '>', '<=', '>=', ':', '!',
      }.contains(t.lexeme);

  List<Token> _captureUntil(Set<String> terminators) {
    final out = <Token>[];
    var depth = 0;
    while (!_current.isEof) {
      if (depth == 0 && terminators.contains(_current.lexeme)) break;
      final lex = _current.lexeme;
      if (lex == '(' || lex == '[' || lex == '{') depth++;
      if (lex == ')' || lex == ']' || lex == '}') depth--;
      if (depth < 0) break;
      out.add(_advance());
    }
    return out;
  }

  // --------------------------------------------------------------- widgets

  Node _parseChild() {
    if (_current.isIdent('if')) return _parseIf();
    if (_current.isIdent('for')) return _parseFor();
    return _parseWidget();
  }

  WidgetNode _parseWidget() {
    if (_current.type != TokenType.identifier) {
      throw FlxError(
        'expected a widget but found ${_current.describe}',
        _current.span,
        hint: 'widgets start with a capital letter, e.g.  Text("hello")',
      );
    }
    final nameTok = _advance();
    final name = nameTok.lexeme;

    final args = <Arg>[];
    if (_check('(')) {
      _advance();
      while (!_check(')')) {
        args.add(_parseArg(name));
        if (!_match(',') && !_check(')')) {
          throw FlxError(
            "expected ',' or ')' in the arguments of $name but found "
            '${_current.describe}',
            _current.span,
          );
        }
      }
      _expect(')', context: 'to close $name(...)');
    }

    List<Node>? children;
    String? callback;
    Span? callbackSpan;

    if (_check('{')) {
      if (layoutWidgets.containsKey(name)) {
        _advance();
        children = <Node>[];
        while (!_check('}')) {
          if (_current.isEof) {
            throw FlxError(
              "unterminated children block of $name",
              nameTok.span,
              hint: "add a closing '}'",
            );
          }
          children.add(_parseChild());
        }
        _expect('}', context: 'to close the children of $name');
      } else {
        final block = _captureRawBlock(name, nameTok);
        callback = block.$1;
        callbackSpan = block.$2;
      }
    }

    return WidgetNode(
      name: name,
      args: args,
      children: children,
      callback: callback,
      callbackSpan: callbackSpan,
      span: _spanFrom(nameTok),
    );
  }

  /// Slices the raw source between `{` and its matching `}` — callback
  /// bodies are plain Dart and are passed straight through.
  (String, Span) _captureRawBlock(String widget, Token nameTok) {
    final open = _advance(); // `{`
    var depth = 1;
    final bodyStart = open.span.end;
    while (depth > 0) {
      if (_current.isEof) {
        throw FlxError(
          'unterminated callback body of $widget',
          open.span,
          hint: "add a closing '}'",
        );
      }
      final t = _advance();
      if (t.lexeme == '{') depth++;
      if (t.lexeme == '}') {
        depth--;
        if (depth == 0) {
          return (
            source.text.substring(bodyStart, t.span.start),
            Span(source, bodyStart, t.span.start),
          );
        }
      }
    }
    throw StateError('unreachable');
  }

  Arg _parseArg(String widget) {
    final start = _current;
    String? name;
    if (_current.type == TokenType.identifier && _peek(1).lexeme == ':') {
      name = _advance().lexeme;
      _advance(); // `:`
    }
    final tokens = _captureUntil(const {',', ')'});
    if (tokens.isEmpty) {
      throw FlxError(
        name == null
            ? 'empty argument in $widget(...)'
            : "argument '$name:' in $widget(...) has no value",
        _current.span,
      );
    }
    return Arg(
      name: name,
      value: serialize(tokens),
      span: _spanFrom(start),
    );
  }

  IfNode _parseIf() {
    final kw = _advance(); // `if`
    _expect('(',
        context: 'after `if`',
        hint: 'control flow looks like:  if (isReady) { Text("go") }');
    final cond = _captureUntil(const {')'});
    if (cond.isEmpty) {
      throw FlxError('`if` needs a condition', _current.span);
    }
    _expect(')', context: 'to close the `if` condition');

    final then = _parseBlock('if');
    List<Node>? orElse;
    if (_current.isIdent('else')) {
      _advance();
      if (_current.isIdent('if')) {
        orElse = [_parseIf()];
      } else {
        orElse = _parseBlock('else');
      }
    }

    return IfNode(
      condition: serialize(cond),
      then: then,
      orElse: orElse,
      span: _spanFrom(kw),
    );
  }

  ForNode _parseFor() {
    final kw = _advance(); // `for`
    _expect('(',
        context: 'after `for`',
        hint: 'loops look like:  for (todo in todos.value) { Text(todo) }');
    final varTok = _expectIdentifier('a loop variable name');
    if (!_current.isIdent('in')) {
      throw FlxError(
        'expected `in` after the loop variable but found '
        '${_current.describe}',
        _current.span,
        hint: 'loops look like:  for (${varTok.lexeme} in items) { ... }',
      );
    }
    _advance(); // `in`
    final iterable = _captureUntil(const {')'});
    if (iterable.isEmpty) {
      throw FlxError('`for` needs something to iterate over', _current.span);
    }
    _expect(')', context: 'to close the `for` header');

    return ForNode(
      variable: varTok.lexeme,
      iterable: serialize(iterable),
      children: _parseBlock('for'),
      span: _spanFrom(kw),
    );
  }

  List<Node> _parseBlock(String keyword) {
    _expect('{', context: 'to open the `$keyword` body');
    final nodes = <Node>[];
    while (!_check('}')) {
      if (_current.isEof) {
        throw FlxError(
          'unterminated `$keyword` body',
          _current.span,
          hint: "add a closing '}'",
        );
      }
      nodes.add(_parseChild());
    }
    _expect('}', context: 'to close the `$keyword` body');
    if (nodes.isEmpty) {
      throw FlxError(
        'empty `$keyword` body renders nothing',
        _spanFrom(_tokens[_pos - 1]),
        hint: 'remove it, or add a widget inside',
      );
    }
    return nodes;
  }
}
