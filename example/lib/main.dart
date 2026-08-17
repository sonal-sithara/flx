import 'package:flutter/material.dart';
import 'package:flx/flx.dart';

import 'data/todos_view_model.dart';
import 'data/user_repository.dart';
import 'pages/routes.g.dart';

/// Everything the app depends on is registered once, here. Screens resolve
/// what they need with `useInject<T>()`, so a test can swap any of it for a
/// fake by registering a different provider.
Injector buildInjector() => Injector()
  ..singleton<UserRepository>((_) => UserRepository())
  ..singleton<TodosViewModel>((_) => TodosViewModel());

void main() {
  runApp(
    FlxScope(
      injector: buildInjector(),
      child: const App(),
    ),
  );
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    // Built from the @page annotations flxc found in lib/pages.
    final router = AppRouter(appRoutes);
    return MaterialApp(
      title: 'flx',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      initialRoute: '/profile',
      onGenerateRoute: router.onGenerateRoute,
    );
  }
}
