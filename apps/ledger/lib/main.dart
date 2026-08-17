import 'package:flutter/material.dart';
import 'package:flx_runtime/flx_runtime.dart';

import 'data/insights.dart';
import 'data/ledger_repository.dart';
import 'data/overview_view_models.dart';
import 'data/security.dart';
import 'data/session_view_models.dart';
import 'data/storage.dart';
import 'data/transactions_view_models.dart';
import 'pages/routes.g.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = await PrefsStorage.open();
  final repository = LedgerRepository(storage);
  final lock = PinLock(storage);

  // Both are loaded before the first frame, so no screen has to render an
  // "initialising" state or guard against half-loaded data.
  await Future.wait([repository.load(), lock.load()]);

  runApp(LedgerApp(injector: buildInjector(repository: repository, lock: lock)));
}

/// The whole object graph, in one place.
///
/// Every screen resolves what it needs with `useInject`/`useViewModel`, so a
/// widget test builds the same graph over a [MemoryStorage] and swaps any
/// single piece.
Injector buildInjector({
  required LedgerRepository repository,
  required PinLock lock,
}) {
  final injector = Injector()
    ..value<LedgerRepository>(repository)
    ..value<PinLock>(lock)
    ..singleton<LockViewModel>((_) => LockViewModel(lock))
    ..singleton<DashboardViewModel>((_) => DashboardViewModel(repository))
    ..singleton<TransactionsViewModel>((_) => TransactionsViewModel(repository))
    ..singleton<TransactionFormViewModel>(
        (_) => TransactionFormViewModel(repository))
    ..singleton<AccountsViewModel>((_) => AccountsViewModel(repository))
    ..singleton<CategoriesViewModel>((_) => CategoriesViewModel(repository))
    ..singleton<InsightsService>((_) => InsightsService(repository));

  // Resolved through the injector so it shares the one LockViewModel the
  // lock screen is bound to — two instances would let "Lock now" do nothing.
  injector.singleton<SettingsViewModel>(
    (i) => SettingsViewModel(lock, repository, i.get<LockViewModel>()),
  );
  return injector;
}

class LedgerApp extends StatelessWidget {
  const LedgerApp({required this.injector, super.key});

  final Injector injector;

  @override
  Widget build(BuildContext context) =>
      FlxScope(injector: injector, child: const _Root());
}

/// A Composable so the theme can follow the settings ViewModel — the app
/// itself is as reactive as any screen.
class _Root extends Composable {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final settings = useViewModel<SettingsViewModel>();
    final lock = useInject<LockViewModel>();
    final router = useMemoized(() => AppRouter(appRoutes));

    return MaterialApp(
      title: 'Ledger',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
      // A configured PIN sends the first frame to the lock screen.
      initialRoute: lock.requiresUnlock ? '/lock' : '/',
      onGenerateRoute: router.onGenerateRoute,
    );
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
        useMaterial3: true,
        brightness: brightness,
        colorSchemeSeed: const Color(0xFF2E7D32),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      );
}
