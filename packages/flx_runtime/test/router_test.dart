import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flx_runtime/flx_runtime.dart';

Widget _stub(Map<String, String> params) => Text(
      params.isEmpty ? 'none' : params.toString(),
      textDirection: TextDirection.ltr,
    );

void main() {
  group('RouteDef.match', () {
    test('matches a literal path', () {
      final route = RouteDef('/settings', _stub);
      expect(route.match('/settings'), isEmpty);
      expect(route.match('/profile'), isNull);
    });

    test('captures a path parameter', () {
      final route = RouteDef('/user/:id', _stub);
      expect(route.match('/user/42'), {'id': '42'});
    });

    test('captures several parameters', () {
      final route = RouteDef('/org/:org/repo/:repo', _stub);
      expect(route.match('/org/flutter/repo/flx'),
          {'org': 'flutter', 'repo': 'flx'});
    });

    test('rejects a different segment count', () {
      final route = RouteDef('/user/:id', _stub);
      expect(route.match('/user'), isNull);
      expect(route.match('/user/42/posts'), isNull);
    });

    test('rejects a mismatched literal segment', () {
      final route = RouteDef('/user/:id', _stub);
      expect(route.match('/account/42'), isNull);
    });

    test('merges query parameters', () {
      final route = RouteDef('/user/:id', _stub);
      expect(route.match('/user/42?tab=posts&sort=new'),
          {'id': '42', 'tab': 'posts', 'sort': 'new'});
    });

    test('matches the root path', () {
      expect(RouteDef('/', _stub).match('/'), isEmpty);
    });

    test('decodes percent-encoded segments', () {
      final route = RouteDef('/search/:q', _stub);
      expect(route.match('/search/hello%20world'), {'q': 'hello world'});
    });
  });

  group('AppRouter', () {
    Future<void> pumpApp(WidgetTester tester, String initialRoute) async {
      final router = AppRouter([
        RouteDef('/', (_) => const Text('home',
            textDirection: TextDirection.ltr)),
        RouteDef('/user/:id', (params) => Text('user ${params['id']}',
            textDirection: TextDirection.ltr)),
      ]);

      await tester.pumpWidget(MaterialApp(
        initialRoute: initialRoute,
        onGenerateRoute: router.onGenerateRoute,
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('routes to a literal path', (tester) async {
      await pumpApp(tester, '/');
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('routes with a parameter', (tester) async {
      await pumpApp(tester, '/user/7');
      expect(find.text('user 7'), findsOneWidget);
    });

    testWidgets('unknown paths land on the 404 screen', (tester) async {
      await pumpApp(tester, '/nope');
      expect(find.textContaining('404'), findsOneWidget);
      expect(find.textContaining('/nope'), findsOneWidget);
    });

    testWidgets('the first matching route wins', (tester) async {
      final router = AppRouter([
        RouteDef('/a/:x', (_) => const Text('first',
            textDirection: TextDirection.ltr)),
        RouteDef('/a/b', (_) => const Text('second',
            textDirection: TextDirection.ltr)),
      ]);

      await tester.pumpWidget(MaterialApp(
        initialRoute: '/a/b',
        onGenerateRoute: router.onGenerateRoute,
      ));
      await tester.pumpAndSettle();

      expect(find.text('first'), findsOneWidget);
    });
  });
}
