import 'package:flxc/flxc.dart';
import 'package:test/test.dart';

/// Error messages are a feature, so they get tested like one: the right
/// message, at the right line and column, with a useful hint.
void main() {
  final compiler = Compiler();

  FlxError errorFor(String src) {
    try {
      compiler.compileSource(Source('test.flx', src));
    } on FlxError catch (e) {
      return e;
    }
    fail('expected a FlxError but compilation succeeded');
  }

  void expectError(
    String src, {
    required Object message,
    int? line,
    int? column,
    Object? hint,
  }) {
    final error = errorFor(src);
    expect(error.message, message);
    if (line != null) expect(error.span?.line, line, reason: 'line');
    if (column != null) expect(error.span?.column, column, reason: 'column');
    if (hint != null) expect(error.hint, hint);
  }

  group('lexer', () {
    test('unterminated string reports the opening quote', () {
      expectError(
        'composable A {\n  Text("oops)\n}\n',
        message: 'unterminated string literal',
        line: 2,
        column: 8,
      );
    });

    test('unterminated block comment', () {
      expectError(
        '/* never closed\ncomposable A { Text("x") }\n',
        message: 'unterminated block comment',
        line: 1,
        column: 1,
      );
    });

    test('unterminated interpolation', () {
      expectError(
        'composable A {\n  Text("hi \${name")\n}\n',
        message: 'unterminated interpolation in string literal',
      );
    });
  });

  group('parser', () {
    test('missing closing paren points at the offending token', () {
      expectError(
        'composable A {\n  Text("hi"\n}\n',
        message: contains("expected ',' or ')'"),
        line: 3,
      );
    });

    test('lowercase composable name is rejected with a fix', () {
      expectError(
        'composable greeting {\n  Text("hi")\n}\n',
        message: "composable 'greeting' must start with a capital letter",
        line: 1,
        column: 12,
        hint: contains("'Greeting'"),
      );
    });

    test('two root widgets', () {
      expectError(
        'composable A {\n  Text("one")\n  Text("two")\n}\n',
        message: "composable 'A' has more than one root widget",
        line: 3,
        hint: contains('Column'),
      );
    });

    test('val after the widget tree', () {
      expectError(
        'composable A {\n  Text("hi")\n  val x = useState(0)\n}\n',
        message: '`val` declarations must come before the widget tree',
        line: 3,
      );
    });

    test('empty composable', () {
      expectError(
        'composable A {\n}\n',
        message: "composable 'A' has no widget to render",
      );
    });

    test('val with no initialiser', () {
      expectError(
        'composable A {\n  val x\n  Text("hi")\n}\n',
        message: contains("expected '='"),
        line: 3,
      );
    });

    test('unknown annotation', () {
      expectError(
        '@route("/a")\ncomposable A {\n  Text("hi")\n}\n',
        message: "unknown annotation '@route'",
        line: 1,
        hint: contains('@page'),
      );
    });

    test('route must start with a slash', () {
      expectError(
        '@page("profile")\ncomposable A {\n  Text("hi")\n}\n',
        message: "route 'profile' must start with '/'",
        hint: contains('"/profile"'),
      );
    });

    test('for without in', () {
      expectError(
        'composable A {\n  Column {\n    for (x of items) { Text(x) }\n  }\n}\n',
        message: contains('expected `in`'),
        line: 3,
        hint: contains('for (x in items)'),
      );
    });

    test('empty if body', () {
      expectError(
        'composable A {\n  Column {\n    if (flag) { }\n  }\n}\n',
        message: 'empty `if` body renders nothing',
      );
    });
  });

  group('routes', () {
    test('route param with no matching composable parameter', () {
      expectError(
        '@page("/user/:id")\ncomposable UserScreen {\n  Text("hi")\n}\n',
        message: contains("captures ':id'"),
        hint: contains('composable Name(id)'),
      );
    });

    test('route param declared as a non-String type', () {
      expectError(
        '@page("/user/:id")\ncomposable UserScreen(id: int) {\n  Text("hi")\n}\n',
        message: contains("must be a String, but is declared as 'int'"),
        hint: contains('int.parse'),
      );
    });
  });

  group('block lambdas and interop', () {
    test('a `=>` block must produce a widget', () {
      expectError(
        'composable A {\n  Builder { context =>\n  }\n}\n',
        message: 'a `=>` block must produce a widget',
        hint: contains('`->`'),
      );
    });

    test('a Dart set literal in an argument is left alone', () {
      // `{ value }` is a set, not a lambda. Only `=>` or `->` after the
      // names makes it a block, so ordinary Dart still passes through.
      final dart = compiler.compileSource(
        Source('test.flx', 'composable A {\n  Thing(cb: { value })\n}\n'),
      );
      expect(dart, contains('Thing(cb: {value})'));
    });

    test('an unterminated block lambda is reported at its opening brace', () {
      expectError(
        'composable A {\n  Builder { context =>\n    Text("hi")\n',
        message: 'unterminated block lambda',
      );
    });

    test('an empty ( ) child is rejected', () {
      expectError(
        'composable A {\n  Column {\n    ()\n  }\n}\n',
        message: 'empty ( ) expression',
      );
    });

    test('an unterminated ( ) child is reported', () {
      expectError(
        'composable A {\n  Column {\n    (a ? B() : C()\n',
        message: 'unterminated ( ... ) expression',
        hint: contains("')'"),
      );
    });

    test('`...` needs something to spread', () {
      expectError(
        'composable A {\n  Column {\n    ...\n  }\n}\n',
        message: 'expected an expression after `...`',
      );
    });

    test('`...` cannot be a composable root', () {
      expectError(
        'composable A {\n  ...rows\n}\n',
        message: '`...` cannot be the root of a composable',
        hint: contains('Column'),
      );
    });
  });

  group('parameter types', () {
    test('an untyped parameter called as a function is caught early', () {
      // Left alone this becomes a String, and Dart reports "the expression
      // doesn't evaluate to a function" inside generated code, naming neither
      // the parameter nor its type.
      expectError(
        'composable Row2(label, onDelete) {\n'
        '  Button(label) {\n'
        '    onDelete()\n'
        '  }\n'
        '}\n',
        message: contains("parameter 'onDelete' is called as a function"),
        line: 1,
        column: 24,
        hint: contains('VoidCallback'),
      );
    });

    test('an explicit type is left alone', () {
      final dart = compiler.compileSource(Source(
        'test.flx',
        'composable Row2(label, onDelete: VoidCallback) {\n'
        '  Button(label) {\n'
        '    onDelete()\n'
        '  }\n'
        '}\n',
      ));
      expect(dart, contains('final VoidCallback onDelete;'));
    });

    test('a method call on another object is not mistaken for one', () {
      final dart = compiler.compileSource(Source(
        'test.flx',
        'composable Row2(label) {\n'
        '  Button(label) {\n'
        '    vm.label()\n'
        '  }\n'
        '}\n',
      ));
      expect(dart, contains('vm.label()'));
    });
  });

  group('constructs that used to fail silently', () {
    test('`switch` as a child names the expression form', () {
      expectError(
        'composable A {\n  Column {\n    switch (m) { case 1: Text("x") }\n  }\n}\n',
        message: contains('`switch` is a statement'),
        hint: contains('parenthesise it'),
      );
    });

    test('`if` as an argument value is rejected', () {
      // Dart has no if-expression; this once emitted code that could not
      // compile, with no warning.
      expectError(
        'composable A {\n  Text(if (flag) "yes" else "no")\n}\n',
        message: '`if` is not an expression in Dart',
        hint: contains('flag ? "yes" : "no"'),
      );
    });

    test('two @page routes on one composable', () {
      // The second silently replaced the first.
      expectError(
        '@page("/a")\n@page("/b")\ncomposable A {\n  Text("hi")\n}\n',
        message: 'a composable can only have one @page route',
        line: 2,
        hint: contains('silently replaced'),
      );
    });

    test('a statement without a semicolon is diagnosed as such', () {
      expectError(
        'composable A {\n  val vm = useViewModel<V>()\n  vm.warmUp()\n'
        '  Text("hi")\n}\n',
        message: contains('more than one root widget'),
        hint: contains("statements end with ';'"),
      );
    });
  });

  group('constructs that must work', () {
    String compile(String src) =>
        compiler.compileSource(Source('test.flx', src));

    test('a binding ends at its line, so the next statement survives', () {
      final dart = compile(
        'composable A {\n  val vm = useViewModel<V>()\n  vm.warmUp();\n'
        '  Text("hi")\n}\n',
      );
      expect(dart, contains('final vm = useViewModel<V>();'));
      expect(dart, contains('vm.warmUp();'));
    });

    test('a wrapped expression is still one binding', () {
      final dart = compile(
        'composable A {\n  val total = items\n      .map(size)\n'
        '      .fold(0, add)\n  Text("hi")\n}\n',
      );
      expect(dart, contains('final total = items.map(size).fold(0, add);'));
    });

    test('await makes a callback async', () {
      final dart = compile(
        'composable A {\n  Button("go") {\n    await vm.save()\n  }\n}\n',
      );
      expect(dart, contains('() async {'));
    });

    test('const children, bare references and typed bindings', () {
      final dart = compile(
        'composable A {\n  val header: Widget = Text("h")\n  Column {\n'
        '    const Text("c")\n    header\n  }\n}\n',
      );
      expect(dart, contains('final Widget header = Text("h");'));
      expect(dart, contains('const Text("c")'));
      expect(dart, contains('      header,'),
          reason: 'a bare name is a reference, not a call');
    });

    test('generic composables and function-type parameters', () {
      final dart = compile(
        'composable Box<T>(item: T, render: String Function(T)) {\n'
        '  Text(render(item))\n}\n',
      );
      expect(dart, contains('class Box<T> extends Composable'));
      expect(dart, contains('final String Function(T) render;'));
    });

    test('import prefixes and combinators survive', () {
      final dart = compile(
        'import "package:a/a.dart" as a\n'
        'import "package:b/b.dart" show One hide Two\n'
        'composable A {\n  Text("hi")\n}\n',
      );
      expect(dart, contains("import 'package:a/a.dart' as a;"));
      expect(dart, contains("import 'package:b/b.dart' show One hide Two;"));
    });

    test('top-level Dart is emitted verbatim, before the composables', () {
      final dart = compile(
        'enum Mode { light, dark }\n\n'
        'int twice(int x) => x * 2;\n\n'
        'composable A {\n  Text("hi")\n}\n',
      );
      expect(dart, contains('enum Mode { light, dark }'));
      expect(dart, contains('int twice(int x) => x * 2;'));
      expect(dart.indexOf('enum Mode'), lessThan(dart.indexOf('class A')));
    });

    test('typed lambda parameters', () {
      final dart = compile(
        'composable A {\n  Thing(onPick: { String v -> vm.set(v); })\n}\n',
      );
      expect(dart, contains('onPick: (String v) {'));
    });
  });

  group('lexing and file-level hazards', () {
    String compile(String src) =>
        compiler.compileSource(Source('test.flx', src));

    test('hex literals survive — every colour is written that way', () {
      // Scanning only decimal digits split 0xFF00AA into `0` and the
      // identifier `xFF00AA`, then re-joined them with a space.
      final dart = compile('composable A {\n  Box(c: 0xFF00AA)\n}\n');
      expect(dart, contains('c: 0xFF00AA'));
    });

    test('digit separators survive', () {
      final dart = compile('composable A {\n  Box(n: 1_000_000)\n}\n');
      expect(dart, contains('n: 1_000_000'));
    });

    test('a sign binds to its number, an operator does not', () {
      final dart = compile(
        'composable A {\n  Box(a: -8, b: -1.5, c: x - y)\n}\n',
      );
      expect(dart, contains('a: -8'));
      expect(dart, contains('b: -1.5'));
      expect(dart, contains('c: x - y'));
    });

    test('exponents and member access on a number still work', () {
      final dart = compile(
        'composable A {\n  Box(a: 1.5e3, b: 2E-2, c: 1.toString())\n}\n',
      );
      expect(dart, contains('a: 1.5e3'));
      expect(dart, contains('b: 2E-2'));
      expect(dart, contains('c: 1.toString()'));
    });

    test('null-aware spread keeps its operator', () {
      final dart = compile(
        'composable A {\n  Column {\n    ...?maybe\n  }\n}\n',
      );
      expect(dart, contains('...?maybe'));
    });

    test('two composables with the same name are rejected', () {
      // This produced two Dart classes of the same name, failing much later
      // and much less clearly.
      expectError(
        'composable A {\n  Text("one")\n}\n\n'
        'composable A {\n  Text("two")\n}\n',
        message: "'A' is declared twice in this file",
        hint: contains('distinct'),
      );
    });

    test('a route capturing the same name twice is rejected', () {
      expectError(
        '@page("/u/:id/p/:id")\ncomposable A(id) {\n  Text(id)\n}\n',
        message: contains("captures ':id' twice"),
        hint: contains('only the last one'),
      );
    });

    test('a builder block on a container widget is rejected', () {
      expectError(
        'composable A {\n  Screen(title: "x") { ctx =>\n    Text("hi")\n  }\n}\n',
        message: 'the block of Screen holds children, not a builder',
        hint: contains('drop the parameters'),
      );
    });

    test('comments between arguments are ignored', () {
      final dart = compile(
        'composable A {\n  Tile(\n    title: "hi", // trailing\n'
        '    /* block */ subtitle: "there",\n  )\n}\n',
      );
      expect(dart, contains('Tile(title: "hi", subtitle: "there")'));
    });

    test('triple-quoted strings keep their newlines', () {
      final dart = compile(
        'composable A {\n  Text("""one\ntwo""")\n}\n',
      );
      expect(dart, contains('"""one\ntwo"""'));
    });

    test('unicode in strings survives', () {
      final dart = compile(
        'composable A {\n  Text("héllo 🎉 日本語")\n}\n',
      );
      expect(dart, contains('héllo 🎉 日本語'));
    });
  });

  group('whitespace and line endings', () {
    String compile(String src) =>
        compiler.compileSource(Source('test.flx', src));

    test('CRLF files behave like LF ones', () {
      // Bindings end at their line, so the line arithmetic has to survive
      // Windows endings.
      final dart = compile(
        'composable A {\r\n  val vm = useViewModel<V>()\r\n'
        '  vm.warmUp();\r\n  Text("hi")\r\n}\r\n',
      );
      expect(dart, contains('final vm = useViewModel<V>();'));
      expect(dart, contains('vm.warmUp();'));
    });

    test('tabs indent as well as spaces', () {
      final dart = compile(
        'composable A {\n\tval x = useState(0)\n\tText("hi")\n}\n',
      );
      expect(dart, contains('final x = useState(0);'));
    });

    test('an expression wrapped after an operator stays one binding', () {
      final dart = compile(
        'composable A {\n  val total = a +\n      b +\n      c\n'
        '  Text("hi")\n}\n',
      );
      expect(dart, contains('final total = a + b + c;'));
    });

    test('an expression wrapped before an operator stays one binding', () {
      final dart = compile(
        'composable A {\n  val total = a\n      + b\n      + c\n'
        '  Text("hi")\n}\n',
      );
      expect(dart, contains('final total = a + b + c;'));
    });

    test('a multi-line collection stays one binding', () {
      final dart = compile(
        'composable A {\n  val items = [\n    1,\n    2,\n  ]\n'
        '  Text("hi")\n}\n',
      );
      expect(dart, contains('final items = [1, 2,];'));
    });

    test('a file with no trailing newline parses', () {
      expect(compile('composable A {\n  Text("hi")\n}'), contains('class A'));
    });

    test('deep nesting does not blow the stack', () {
      final buffer = StringBuffer('composable A {\n');
      for (var i = 0; i < 60; i++) {
        buffer.write('Column {\n');
      }
      buffer.write('Text("deep")\n');
      for (var i = 0; i < 60; i++) {
        buffer.write('}\n');
      }
      buffer.write('}\n');

      expect(compile(buffer.toString()), contains('Text("deep")'));
    });
  });

  group('codegen', () {
    test('unknown shorthand type', () {
      expectError(
        'composable A {\n  Text("hi", weird: .thing)\n}\n',
        message: contains("doesn't know what type '.thing' belongs to"),
      );
    });

    test('flag modifier rejects a non-boolean', () {
      expectError(
        'composable A {\n  Column(center: 12) {\n    Text("hi")\n  }\n}\n',
        message: contains('is a flag and only accepts true or false'),
      );
    });

    test('a val cannot use an earlier useFetch result', () {
      expectError(
        'composable A {\n'
        '  val user = useFetch(api.currentUser)\n'
        '  val posts = useFetch(api.postsFor(user.id))\n'
        '  Text("hi")\n'
        '}\n',
        message: "val 'posts' uses 'user' before it has loaded",
        line: 3,
        hint: contains(r'user$.data'),
      );
    });

    test('if cannot be the root of a composable', () {
      expectError(
        'composable A {\n  if (flag) { Text("hi") }\n}\n',
        message: '`if` cannot be the root of a composable',
        hint: contains('Column'),
      );
    });
  });

  group('rendering', () {
    test('renders file:line:col with a caret under the problem', () {
      final error = errorFor('composable greeting {\n  Text("hi")\n}\n');
      final rendered = error.render();

      expect(rendered, startsWith('error: '));
      expect(rendered, contains('--> test.flx:1:12'));
      expect(rendered, contains('composable greeting {'));
      expect(rendered, contains('^'));
      expect(rendered, contains('= hint:'));
    });

    test('caret sits under the right column', () {
      final error = errorFor('composable greeting {\n  Text("hi")\n}\n');
      final lines = error.render().split('\n');
      // The echoed source line is the one carrying the `1 | ` gutter — not
      // the error message above it, which also contains the word.
      final sourceLine = lines.firstWhere((l) => l.startsWith('1 | '));
      final caretLine = lines.firstWhere((l) => l.contains('^'));

      // Both lines share the `N | ` gutter, so columns line up directly.
      expect(caretLine.indexOf('^'), sourceLine.indexOf('greeting'));
    });
  });
}
