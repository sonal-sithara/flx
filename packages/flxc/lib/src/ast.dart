import 'source.dart';

/// One parsed `.flx` file.
class FlxFile {
  FlxFile({
    required this.source,
    required this.imports,
    required this.composables,
  });

  final Source source;
  final List<ImportDecl> imports;

  /// A file may declare several composables: one screen plus the small
  /// components it is built from. Only those with a [ComposableDecl.route]
  /// become entries in the generated route table.
  final List<ComposableDecl> composables;
}

class ImportDecl {
  ImportDecl(this.rawUri, this.span);

  /// The literal as written, quotes included: `"../data/user_repository.dart"`.
  final String rawUri;
  final Span span;

  /// Normalised to Dart's single-quote convention.
  String get dartLiteral {
    final inner = rawUri.substring(1, rawUri.length - 1);
    return "'$inner'";
  }
}

class Param {
  Param(this.name, this.type, this.span, {this.defaultValue});

  final String name;
  final String type;
  final Span span;

  /// Serialized default, e.g. `0` in `composable Badge(count: int = 0)`.
  final String? defaultValue;

  bool get isRequired => defaultValue == null;

  /// Params flow in from route params as strings, so only `String` can be
  /// filled from a URL without a converter.
  bool get isRoutable => type == 'String';
}

class ValDecl {
  ValDecl(this.name, this.expr, this.span, this.references);

  final String name;

  /// The right-hand side, already serialized to Dart.
  final String expr;
  final Span span;

  /// Every identifier the right-hand side mentions. Used to catch a val
  /// reaching for a value that does not exist yet at that point.
  final Set<String> references;

  /// `useFetch(...)` results get unwrapped through `AsyncValue.when`, so the
  /// UI below can treat `user` as the resolved value.
  bool get isAsync => expr.startsWith('useFetch(') || expr.startsWith('useFetch<');
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
    this.children,
    this.callback,
    this.callbackSpan,
  });

  final String name;
  final List<Arg> args;

  @override
  final Span span;

  /// Present for layout widgets with a `{ ... }` block.
  final List<Node>? children;

  /// Present for non-layout widgets with a `{ ... }` block — raw Dart
  /// statements forming a callback body.
  final String? callback;
  final Span? callbackSpan;
}

class Arg {
  Arg({required this.name, required this.value, required this.span});

  /// `null` for positional arguments.
  final String? name;

  /// The argument expression, already serialized to Dart.
  final String value;
  final Span span;

  /// `.title` / `.center` — a leading dot means the DSL is eliding an enum or
  /// class prefix that codegen fills in from the parameter name.
  bool get isShorthand => value.startsWith('.');
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
  });

  final String name;
  final List<Param> params;
  final List<ValDecl> vals;
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
