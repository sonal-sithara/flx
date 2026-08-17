import 'package:flutter/material.dart';

import 'clean_ui/clean_ui.dart';
import 'pages/routes.g.dart';

void main() => runApp(App());

final _router = AppRouter(appRoutes);

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        initialRoute: '/profile',
        onGenerateRoute: _router.onGenerateRoute,
      );
}
