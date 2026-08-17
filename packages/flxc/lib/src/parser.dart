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

/// Widgets whose block binds an element and is rendered lazily, one item at a
/// time: `LazyColumn(items: xs) { x in Text(x.name) }`. Unlike `for`, which
/// builds every child eagerly, these compile to an itemBuilder.
const builderWidgets = <String>{'LazyColumn', 'LazyRow', 'LazyGrid'};

/// Widgets that take their block as a `children:` argument rather than as a
/// list extension. This is how a widget tree reaches a named parameter, which
/// plain arguments cannot express — they are captured as raw expression
/// tokens, not parsed as widgets.
const containerWidgets = <String>{'Screen', 'Panel'};

/// Container widgets that supply their own Scaffold, so `@page` must not add
/// a second one around them.
const scaffoldProviders = <String>{'Screen', 'Scaffold'};

/// The bare widget name, without a named constructor or type arguments:
/// `Image.asset` → `Image`, `LazyColumn<Todo>` → `LazyColumn`.
String baseNameOf(String name) {
  final cut = name.indexOf(RegExp(r'[.<]'));
  return cut < 0 ? name : name.substring(0, cut);
}

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

    final decl = ComposableDecl(
      name: name,
      params: params,
      vals: vals,
      root: root,
      route: route,
      span: _spanFrom(start),
    );
    _checkCallableParams(decl);
    return decl;
  }

  /// Catches a parameter that is called as a function but has no declared
  /// type.
  ///
  /// An untyped parameter defaults to String, which is right for route
  /// params — they arrive from a URL as text. Calling one produces
  /// "the expression doesn't evaluate to a function", pointing at the
  /// generated call site with no mention of the parameter or its type. The
  /// rule is simple once you know it, so the compiler should say it.
  void _checkCallableParams(ComposableDecl decl) {
    final body = source.text.substring(decl.span.start, decl.span.end);

    for (final param in decl.params) {
      if (!param.isTypeImplicit) continue;
      // The name, called: not preceded by an identifier character (so
      // `vm.onDelete(` does not count) and followed by an open paren.
      final called = RegExp('(?<![\\w\$.])${RegExp.escape(param.name)}\\s*\\(');
      if (!called.hasMatch(body)) continue;
      throw FlxError(
        "parameter '${param.name}' is called as a function, but has no "
        'declared type so it defaults to String',
        param.span,
        hint: 'give it one, e.g. '
            '${param.name}: VoidCallback  —  or  '
            '${param.name}: void Function(String)',
      );
    }
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
      var implicit = true;
      if (_match(':')) {
        type = serialize(_captureType());
        implicit = false;
      }
      String? defaultValue;
      if (_match('=')) {
        defaultValue = serialize(_captureUntil(const {',', ')'}));
      }
      params.add(
        Param(
          nameTok.lexeme,
          type,
          _spanFrom(nameTok),
          defaultValue: defaultValue,
          isTypeImplicit: implicit,
        ),
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
    if (_check('(')) return _parseRawChild();
    if (_check('...')) return _parseSpreadChild();
    return _parseWidget();
  }

  /// `(cond ? A() : B())` — a raw Dart expression used as a child.
  ///
  /// The escape hatch. Whatever the DSL has no syntax for can still be
  /// written, so an unsupported construct is never a wall.
  Node _parseRawChild() {
    final open = _expect('(');
    final tokens = <Token>[];
    var depth = 1;
    while (depth > 0) {
      if (_current.isEof) {
        throw FlxError(
          'unterminated ( ... ) expression',
          open.span,
          hint: "add a closing ')'",
        );
      }
      final token = _advance();
      if (token.lexeme == '(') depth++;
      if (token.lexeme == ')') {
        depth--;
        if (depth == 0) break;
      }
      tokens.add(token);
    }
    if (tokens.isEmpty) {
      throw FlxError('empty ( ) expression', _spanFrom(open));
    }
    return RawNode(expression: serialize(tokens), span: _spanFrom(open));
  }

  /// `...expression` — splices a list of widgets into the children.
  Node _parseSpreadChild() {
    final start = _expect('...');
    final tokens = _captureExpression();
    if (tokens.isEmpty) {
      throw FlxError(
        'expected an expression after `...`',
        _current.span,
        hint: 'e.g.  ...vm.extraRows',
      );
    }
    return RawNode(
      expression: serialize(tokens),
      span: _spanFrom(start),
      isSpread: true,
    );
  }

  /// Reads a widget name: `Text`, `Image.asset`, `LazyColumn<Todo>`.
  String _parseWidgetName(Token first) {
    final buffer = StringBuffer(first.lexeme);

    while (_check('.') && _peek(1).type == TokenType.identifier) {
      _advance();
      buffer
        ..write('.')
        ..write(_advance().lexeme);
    }

    if (_check('<')) {
      var depth = 0;
      do {
        final token = _advance();
        if (token.lexeme == '<') depth++;
        if (token.lexeme == '>') depth--;
        buffer.write(token.lexeme);
        if (token.lexeme == ',') buffer.write(' ');
      } while (depth > 0 && !_current.isEof);
    }
    return buffer.toString();
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
    final name = _parseWidgetName(nameTok);
    final base = baseNameOf(name);

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
    var callbackParams = const <String>[];
    String? itemVariable;
    String? indexVariable;

    if (_check('{')) {
      if (_lambdaAhead()) {
        // `LayoutBuilder { ctx, box => ... }` — a trailing block that produces
        // a widget. It becomes the `builder:` argument, which is what every
        // builder-shaped widget in Flutter and its ecosystem calls it.
        final lambda = _parseLambdaPart();
        // A builder that takes parameters is `builder:` everywhere in Flutter
        // and its ecosystem. A zero-argument one is positional by the same
        // convention — GetX's Obx, MobX's Observer. Either way an explicit
        // `name: { ... }` argument overrides the guess.
        final named = lambda.returnsWidget && lambda.params.isNotEmpty;
        args.add(Arg(
          name: named ? 'builder' : null,
          parts: [lambda],
          span: lambda.span,
        ));
      } else if (layoutWidgets.containsKey(base) ||
          containerWidgets.contains(base)) {
        children = _parseChildrenBlock(name, nameTok);
      } else if (builderWidgets.contains(base)) {
        final binding = _parseBuilderBinding(name);
        itemVariable = binding.$1;
        indexVariable = binding.$2;
        children = _parseChildrenBlock(name, nameTok, alreadyOpen: true);
      } else {
        callbackParams = _parseCallbackParams();
        final block = _captureRawBlock(name, nameTok, alreadyOpen: true);
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
      callbackParams: callbackParams,
      itemVariable: itemVariable,
      indexVariable: indexVariable,
      span: _spanFrom(nameTok),
    );
  }

  List<Node> _parseChildrenBlock(
    String name,
    Token nameTok, {
    bool alreadyOpen = false,
  }) {
    if (!alreadyOpen) _advance(); // `{`
    final children = <Node>[];
    while (!_check('}')) {
      if (_current.isEof) {
        throw FlxError(
          'unterminated children block of $name',
          nameTok.span,
          hint: "add a closing '}'",
        );
      }
      children.add(_parseChild());
    }
    _expect('}', context: 'to close the children of $name');
    if (children.isEmpty) {
      throw FlxError(
        '$name has an empty block',
        nameTok.span,
        hint: 'add a child widget, or drop the { }',
      );
    }
    return children;
  }

  /// Consumes `{ item in` or `{ item, index in` from a builder widget.
  (String, String?) _parseBuilderBinding(String name) {
    _expect('{', context: 'to open the $name block');
    final item = _expectIdentifier(
      'the name to bind each item to',
      hint: 'builder blocks look like:  $name(items: xs) { x in ... }',
    );
    String? index;
    if (_match(',')) {
      index = _expectIdentifier('the index name').lexeme;
    }
    if (!_current.isIdent('in')) {
      throw FlxError(
        'expected `in` after the item name but found ${_current.describe}',
        _current.span,
        hint: '$name binds each element: '
            '$name(items: xs) { ${item.lexeme} in ... }',
      );
    }
    _advance(); // `in`
    return (item.lexeme, index);
  }

  /// Consumes `{` plus an optional `a, b ->` parameter list.
  ///
  /// Returns the bound names, empty for a plain `{ ... }` callback. The block
  /// is left open for [_captureRawBlock] to slice.
  List<String> _parseCallbackParams() {
    final open = _pos;
    _expect('{');

    final params = <String>[];
    while (_current.type == TokenType.identifier) {
      params.add(_current.lexeme);
      _advance();
      if (_match(',')) continue;
      break;
    }

    if (params.isNotEmpty && _check('->')) {
      _advance();
      return params;
    }

    // Not a parameter list after all — rewind past `{` and treat the whole
    // block as statements.
    _pos = open + 1;
    return const [];
  }

  /// Slices the raw source between `{` and its matching `}` — callback
  /// bodies are plain Dart and are passed straight through.
  (String, Span) _captureRawBlock(
    String widget,
    Token nameTok, {
    bool alreadyOpen = false,
  }) {
    // When the block is already open the previous token is either the `{` or
    // the `->` that closed the parameter list; the body starts right after it.
    final open = alreadyOpen ? _tokens[_pos - 1] : _advance();
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
    final parts = _parseValueParts(const {',', ')'});
    if (parts.isEmpty) {
      throw FlxError(
        name == null
            ? 'empty argument in $widget(...)'
            : "argument '$name:' in $widget(...) has no value",
        _current.span,
      );
    }
    return Arg(name: name, parts: parts, span: _spanFrom(start));
  }

  /// Parses an argument value: ordinary Dart, with widget trees and block
  /// lambdas recognised wherever they appear — including nested inside a list
  /// or another call.
  ///
  /// This is what lets an argument hold a widget. Without it `body:`, `child:`
  /// and every `builder:` in Flutter are unreachable from the DSL.
  List<ArgPart> _parseValueParts(Set<String> terminators) {
    final parts = <ArgPart>[];
    final buffer = <Token>[];
    var depth = 0;

    void flush() {
      if (buffer.isEmpty) return;
      parts.add(DartText(serialize(buffer)));
      buffer.clear();
    }

    while (!_current.isEof) {
      final lexeme = _current.lexeme;
      if (depth == 0 && terminators.contains(lexeme)) break;

      if (lexeme == '{' && _lambdaAhead()) {
        flush();
        parts.add(_parseLambdaPart());
        continue;
      }
      if (_widgetBlockAhead()) {
        flush();
        parts.add(WidgetPart(_parseWidget()));
        continue;
      }

      if (lexeme == '(' || lexeme == '[' || lexeme == '{') {
        depth++;
      } else if (lexeme == ')' || lexeme == ']' || lexeme == '}') {
        if (depth == 0) break;
        depth--;
      }
      buffer.add(_advance());
    }
    flush();
    return parts;
  }

  /// True when `{` opens a block lambda — `{ a, b => ... }` or `{ a -> ... }`
  /// — rather than a map literal or a Dart block.
  bool _lambdaAhead() {
    var i = _pos + 1;
    while (i < _tokens.length && _tokens[i].type == TokenType.identifier) {
      i++;
      if (i < _tokens.length && _tokens[i].lexeme == ',') {
        i++;
        continue;
      }
      break;
    }
    if (i >= _tokens.length) return false;
    final lexeme = _tokens[i].lexeme;
    return lexeme == '=>' || lexeme == '->';
  }

  /// True when the cursor sits on `Widget(...)  {` — a widget with a block,
  /// as opposed to an ordinary call.
  bool _widgetBlockAhead() {
    if (_current.type != TokenType.identifier) return false;
    if (!_startsWidget(_current)) return false;

    var i = _pos + 1;
    // Named constructor: Image.asset
    while (i + 1 < _tokens.length &&
        _tokens[i].lexeme == '.' &&
        _tokens[i + 1].type == TokenType.identifier) {
      i += 2;
    }
    if (i < _tokens.length && _tokens[i].lexeme == '<') {
      i = _skipBalanced(i, '<', '>');
      if (i < 0) return false;
    }
    if (i < _tokens.length && _tokens[i].lexeme == '(') {
      i = _skipBalanced(i, '(', ')');
      if (i < 0) return false;
    }
    return i < _tokens.length && _tokens[i].lexeme == '{';
  }

  /// Index just past the balanced pair starting at [start], or -1.
  int _skipBalanced(int start, String open, String close) {
    var depth = 0;
    for (var i = start; i < _tokens.length; i++) {
      final lexeme = _tokens[i].lexeme;
      if (lexeme == open) depth++;
      if (lexeme == close) {
        depth--;
        if (depth == 0) return i + 1;
      }
    }
    return -1;
  }

  LambdaPart _parseLambdaPart() {
    final open = _expect('{');
    final params = <String>[];
    while (_current.type == TokenType.identifier) {
      params.add(_advance().lexeme);
      if (_match(',')) continue;
      break;
    }

    if (_match('=>')) {
      final children = <Node>[];
      while (!_check('}')) {
        if (_current.isEof) {
          throw FlxError(
            'unterminated block lambda',
            open.span,
            hint: "add a closing '}'",
          );
        }
        children.add(_parseChild());
      }
      _expect('}', context: 'to close the block lambda');
      if (children.isEmpty) {
        throw FlxError(
          'a `=>` block must produce a widget',
          _spanFrom(open),
          hint: 'use `->` for a block that just runs statements',
        );
      }
      return LambdaPart(
        params: params,
        children: children,
        span: _spanFrom(open),
      );
    }

    _expect('->',
        context: 'after the block lambda parameters',
        hint: 'use `=>` when the block produces a widget, `->` when it just '
            'runs statements');
    final body = _captureRawBody(open);
    return LambdaPart(
      params: params,
      statements: body,
      span: _spanFrom(open),
    );
  }

  /// Raw source up to the `}` matching an already-open block.
  String _captureRawBody(Token open) {
    final bodyStart = _tokens[_pos - 1].span.end;
    var depth = 1;
    while (true) {
      if (_current.isEof) {
        throw FlxError(
          'unterminated block lambda',
          open.span,
          hint: "add a closing '}'",
        );
      }
      final token = _advance();
      if (token.lexeme == '{') depth++;
      if (token.lexeme == '}') {
        depth--;
        if (depth == 0) {
          return source.text.substring(bodyStart, token.span.start);
        }
      }
    }
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
