import 'source.dart';

/// One parsed `.flx` file.
class FlxFile {
  FlxFile({
    required this.source,
    required this.imports,
    required this.composables,
    this.declarations = const [],
  });

  final Source source;
  final List<ImportDecl> imports;

  /// Raw Dart declared at the top level of the `.flx` — enums, helper
  /// functions, private classes, extensions. Emitted verbatim above the
  /// composables, so a screen's helpers can live beside it instead of being
  /// exiled to a separate file.
  final List<String> declarations;

  /// A file may declare several composables: one screen plus the small
  /// components it is built from. Only those with a [ComposableDecl.route]
  /// become entries in the generated route table.
  final List<ComposableDecl> composables;
}

class ImportDecl {
  ImportDecl(this.rawUri, this.span, {this.suffix = ''});

  /// The literal as written, quotes included: `"../data/user_repository.dart"`.
  final String rawUri;
  final Span span;

  /// Everything after the URI: `as m`, `show Button`, `hide Provider`.
  /// Needed the moment two packages export the same name.
  final String suffix;

  /// The full Dart directive, normalised to single quotes.
  String get dartDirective {
    final inner = rawUri.substring(1, rawUri.length - 1);
    return suffix.isEmpty ? "'$inner'" : "'$inner' $suffix";
  }
}

class Param {
  Param(
    this.name,
    this.type,
    this.span, {
    this.defaultValue,
    this.isTypeImplicit = false,
  });

  final String name;
  final String type;
  final Span span;

  /// True when no type was written and `String` was assumed — the right
  /// default for route parameters, which arrive from a URL as text.
  final bool isTypeImplicit;

  /// Serialized default, e.g. `0` in `composable Badge(count: int = 0)`.
  final String? defaultValue;

  bool get isRequired => defaultValue == null;

  /// Params flow in from route params as strings, so only `String` can be
  /// filled from a URL without a converter.
  bool get isRoutable => type == 'String';
}

class ValDecl {
  ValDecl(
    this.name,
    this.expr,
    this.span,
    this.references, {
    this.type,
  });

  final String name;

  /// An explicit annotation: `val count: int = 5`. Null means inferred.
  final String? type;

  /// The right-hand side, already serialized to Dart.
  final String expr;
  final Span span;

  /// Every identifier the right-hand side mentions. Used to catch a val
  /// reaching for a value that does not exist yet at that point.
  final Set<String> references;

  /// Hooks that yield an [AsyncValue] and therefore get unwrapped through
  /// `AsyncValue.when`, so the UI below treats the name as the resolved value.
  static const asyncHooks = {'useFetch', 'useStream'};

  bool get isAsync => asyncHooks.any(
        (hook) => expr.startsWith('$hook(') || expr.startsWith('$hook<'),
      );
}

/// Anything that can appear as a child inside a layout block.
sealed class Node {
  Span get span;
}

class WidgetNode implements Node {
  WidgetNode({
    required this.name,
    required this.args,
    required this.span,
    this.isConst = false,
    this.isReference = false,
    this.children,
    this.callback,
    this.callbackSpan,
    this.callbackParams = const [],
    this.itemVariable,
    this.indexVariable,
  });

  final String name;
  final List<Arg> args;

  @override
  final Span span;

  /// `const Text("hi")` — emitted as a const constructor call.
  final bool isConst;

  /// True when the child is a bare reference to an existing widget value
  /// (`header`) rather than a constructor call (`Header()`).
  final bool isReference;

  /// Present for layout and builder widgets with a `{ ... }` block.
  final List<Node>? children;

  /// Present for non-layout widgets with a `{ ... }` block — raw Dart
  /// statements forming a callback body.
  final String? callback;
  final Span? callbackSpan;

  /// Names bound by a parameterised callback: `{ value -> ... }`.
  final List<String> callbackParams;

  /// The element name bound by a builder block: `{ tx in ... }`.
  final String? itemVariable;

  /// The optional index name: `{ tx, i in ... }`.
  final String? indexVariable;

  bool get isBuilder => itemVariable != null;
}

/// One piece of an argument value.
///
/// An argument is not just an expression: it may contain a widget tree
/// (`body: Column { ... }`) or a block lambda
/// (`builder: { ctx, state => ... }`), possibly nested inside ordinary Dart
/// (`children: [Text("a"), Panel { ... }]`). Capturing arguments as flat token
/// runs is what made every builder-based widget — including Flutter's own —
/// impossible to express.
sealed class ArgPart {}

/// Literal Dart, already serialized.
class DartText implements ArgPart {
  DartText(this.text);
  final String text;
}

/// A widget tree appearing as (part of) an argument value.
class WidgetPart implements ArgPart {
  WidgetPart(this.widget);
  final WidgetNode widget;
}

/// A `{ params => widgets }` or `{ params -> statements }` block.
class LambdaPart implements ArgPart {
  LambdaPart({
    required this.params,
    required this.span,
    this.children,
    this.statements,
  });

  final List<String> params;
  final Span span;

  /// Present for `=>` lambdas, which evaluate to a widget.
  final List<Node>? children;

  /// Present for `->` lambdas, which are raw Dart statements returning void.
  final String? statements;

  bool get returnsWidget => children != null;
}

class Arg {
  Arg({required this.name, required this.parts, required this.span});

  /// `null` for positional arguments.
  final String? name;

  /// The value, in order. Usually a single [DartText].
  final List<ArgPart> parts;
  final Span span;

  /// The value as plain Dart, or null when it contains a widget or a lambda.
  String? get text {
    if (parts.length != 1) return null;
    final part = parts.first;
    return part is DartText ? part.text : null;
  }

  /// `.title` / `.center` — a leading dot means the DSL is eliding an enum or
  /// class prefix that codegen fills in from the parameter name.
  bool get isShorthand => text?.startsWith('.') ?? false;
}

class IfNode implements Node {
  IfNode({
    required this.condition,
    required this.then,
    required this.span,
    this.orElse,
  });

  /// Serialized Dart condition.
  final String condition;
  final List<Node> then;

  /// `null` when there is no `else`. An `else if` chain is represented as a
  /// single-element list holding the nested [IfNode].
  final List<Node>? orElse;

  @override
  final Span span;
}

/// A raw Dart expression used where a child is expected: `(cond ? A() : B())`.
///
/// The escape hatch. Anything the DSL has no syntax for can still be written,
/// so a missing feature is never a wall.
class RawNode implements Node {
  RawNode({required this.expression, required this.span, this.isSpread = false});

  /// Serialized Dart, without the wrapping parentheses.
  final String expression;

  /// `...items` — splices a list of widgets into the surrounding children.
  final bool isSpread;

  @override
  final Span span;
}

class ForNode implements Node {
  ForNode({
    required this.variable,
    required this.iterable,
    required this.children,
    required this.span,
  });

  final String variable;

  /// Serialized Dart expression being iterated.
  final String iterable;
  final List<Node> children;

  @override
  final Span span;
}

class ComposableDecl {
  ComposableDecl({
    required this.name,
    required this.params,
    required this.vals,
    required this.root,
    required this.span,
    this.route,
    this.typeParams = '',
    this.statements = const [],
  });

  final String name;

  /// `<T>` / `<T extends Object>` — carried through to the generated class so
  /// components can be generic.
  final String typeParams;

  final List<Param> params;
  final List<ValDecl> vals;

  /// Raw Dart statements between the bindings and the widget tree.
  final List<String> statements;
  final Node root;
  final Span span;

  /// The `@page("/path")` route, or null for a plain component.
  final String? route;

  bool get isPage => route != null;

  /// Route params in declaration order, e.g. `['id']` for `/user/:id`.
  List<String> get routeParams => routeParamsOf(route);
}

/// Extracts `:param` names from a route pattern.
List<String> routeParamsOf(String? route) {
  if (route == null) return const [];
  return route
      .split('/')
      .where((s) => s.startsWith(':'))
      .map((s) => s.substring(1))
      .toList();
}
