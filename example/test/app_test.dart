import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flx/flx.dart';
import 'package:flx_example/data/todos_view_model.dart';
import 'package:flx_example/data/user_repository.dart';
import 'package:flx_example/main.dart';

/// End-to-end tests over the *generated* screens.
///
/// Nothing here imports a `.dart` produced by flxc directly — the app is
/// booted exactly as `main()` does it, so a codegen regression fails here.
class FakeUserRepository implements UserRepository {
  @override
  Future<User> currentUser() async => const User('Grace Hopper', null);
}

class SlowUserRepository implements UserRepository {
  SlowUserRepository(this.completer);
  final Completer<User> completer;

  @override
  Future<User> currentUser() => completer.future;
}

Widget boot(Injector injector) =>
    FlxScope(injector: injector, child: const App());

Injector testInjector({UserRepository? users}) => Injector()
  ..singleton<UserRepository>((_) => users ?? FakeUserRepository())
  ..singleton<TodosViewModel>((_) => TodosViewModel());

void main() {
  testWidgets('profile shows a spinner, then the fetched user',
      (tester) async {
    final completer = Completer<User>();
    await tester.pumpWidget(
      boot(testInjector(users: SlowUserRepository(completer))),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(const User('Grace Hopper', null));
    await tester.pumpAndSettle();

    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('useState drives the tap counter', (tester) async {
    await tester.pumpWidget(boot(testInjector()));
    await tester.pumpAndSettle();

    expect(find.text('Taps: 0'), findsOneWidget);
    await tester.tap(find.text('Tap me'));
    await tester.pump();
    expect(find.text('Taps: 1'), findsOneWidget);
  });

  testWidgets('navigates by object push', (tester) async {
    await tester.pumpWidget(boot(testInjector()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Dark mode: false'), findsOneWidget);
  });

  testWidgets('navigates by path through the generated route table',
      (tester) async {
    await tester.pumpWidget(boot(testInjector()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open user 42'));
    await tester.pumpAndSettle();

    // Proves routes.g.dart matched /user/:id and passed the param through.
    expect(find.text('User id: 42'), findsOneWidget);
  });

  testWidgets('DSL if/else and for render the todo list', (tester) async {
    await tester.pumpWidget(boot(testInjector()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Todos'));
    await tester.pumpAndSettle();

    // `for (todo in vm.todos)` — collection-for over the ViewModel.
    expect(find.text('• Learn flx'), findsOneWidget);
    expect(find.text('✓ Port the transpiler to Dart'), findsOneWidget);
    expect(find.text('2 remaining'), findsOneWidget);
  });

  testWidgets('the ViewModel rebuilds the screen on notify', (tester) async {
    await tester.pumpWidget(boot(testInjector()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todos'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add a todo'));
    await tester.pump();

    expect(find.text('3 remaining'), findsOneWidget);
    expect(find.text('• Task 4'), findsOneWidget);
  });

  testWidgets('clearing completed todos updates the list', (tester) async {
    await tester.pumpWidget(boot(testInjector()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todos'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear completed'));
    await tester.pump();

    expect(find.text('✓ Port the transpiler to Dart'), findsNothing);
    expect(find.text('• Learn flx'), findsOneWidget);
  });

  testWidgets('back navigation returns to profile', (tester) async {
    await tester.pumpWidget(boot(testInjector()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Todos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Grace Hopper'), findsOneWidget);
  });

  testWidgets('an unknown deep link lands on the 404 screen', (tester) async {
    final router = AppRouter(const []);
    await tester.pumpWidget(MaterialApp(
      initialRoute: '/does-not-exist',
      onGenerateRoute: router.onGenerateRoute,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('404'), findsOneWidget);
  });
}
