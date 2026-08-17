import 'package:flutter/material.dart';

import 'core.dart';

/// Theme access without touching context.
ThemeData useTheme() => Theme.of(useContext());

TextTheme useTextTheme() => Theme.of(useContext()).textTheme;

ColorScheme useColorScheme() => Theme.of(useContext()).colorScheme;

/// Media query / screen info.
MediaQueryData useMediaQuery() => MediaQuery.of(useContext());

Size useScreenSize() => MediaQuery.sizeOf(useContext());

/// Navigation. Capture in a val during build, call inside callbacks.
NavigatorState useNavigator() => Navigator.of(useContext());

extension NavigatorX on NavigatorState {
  /// Push a screen object directly: nav.to(SettingsScreen())
  Future<T?> to<T>(Widget page) =>
      push<T>(MaterialPageRoute<T>(builder: (_) => page));

  /// Navigate by path via the generated route table: nav.toPath('/user/42')
  Future<T?> toPath<T extends Object?>(String path) => pushNamed<T>(path);
}
