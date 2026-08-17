import 'package:flutter/material.dart';

/// One route pattern → screen builder. Patterns support :params:
///   RouteDef('/user/:id', (params) => UserScreen(id: params['id'] ?? ''))
class RouteDef {
  RouteDef(this.pattern, this.builder)
      : _segments = pattern.split('/').where((s) => s.isNotEmpty).toList();

  final String pattern;
  final Widget Function(Map<String, String> params) builder;
  final List<String> _segments;

  /// Returns extracted params if [path] matches, else null.
  /// Query parameters (?a=b) are merged into the map.
  Map<String, String>? match(String path) {
    final uri = Uri.parse(path);
    final parts = uri.pathSegments;
    if (parts.length != _segments.length) return null;
    final params = <String, String>{};
    for (var i = 0; i < _segments.length; i++) {
      final s = _segments[i];
      if (s.startsWith(':')) {
        params[s.substring(1)] = parts[i];
      } else if (s != parts[i]) {
        return null;
      }
    }
    params.addAll(uri.queryParameters);
    return params;
  }
}

/// Plug into MaterialApp:
///   onGenerateRoute: AppRouter(appRoutes).onGenerateRoute
/// Deep links, web URLs, and pushNamed calls all arrive here.
class AppRouter {
  AppRouter(this.routes);

  final List<RouteDef> routes;

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final name = settings.name ?? '/';
    for (final r in routes) {
      final params = r.match(name);
      if (params != null) {
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => r.builder(params),
        );
      }
    }
    return MaterialPageRoute(
      settings: settings,
      builder: (_) => Scaffold(
        body: Center(child: Text('404 — no route for "$name"')),
      ),
    );
  }
}
