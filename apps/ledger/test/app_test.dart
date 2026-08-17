import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flx/flx.dart';
import 'package:ledger/data/insights.dart';
import 'package:ledger/data/ledger_repository.dart';
import 'package:ledger/data/security.dart';
import 'package:ledger/data/storage.dart';
import 'package:ledger/domain/models.dart';
import 'package:ledger/main.dart';

/// End-to-end tests over the screens flxc generated from `lib/pages/*.flx`.
///
/// Nothing here imports a generated `.dart` directly — the app is booted the
/// way `main()` boots it, so a codegen or runtime regression fails here.
class Harness {
  Harness(this.storage, this.repository, this.lock, this.injector);

  final MemoryStorage storage;
  final LedgerRepository repository;
  final PinLock lock;
  final Injector injector;

  Widget get app => LedgerApp(injector: injector);
}

/// Builds the real object graph over in-memory storage — no plugins, no
/// platform channels. This is the payoff of putting Storage behind an
/// interface.
Future<Harness> boot({String? pin}) async {
  final storage = MemoryStorage();
  final repository = LedgerRepository(storage);
  final lock = PinLock(storage);
  await repository.load();
  await lock.load();
  if (pin != null) await lock.setPin(pin);

  return Harness(
    storage,
    repository,
    lock,
    buildInjector(repository: repository, lock: lock),
  );
}

/// Taps by text, scrolling it into view first.
///
/// The dashboard and the transaction form are both scrollable and taller than
/// the 800x600 test viewport, so a plain `tap` silently misses anything below
/// the fold.
Future<void> tapText(WidgetTester tester, String text, {int index = 0}) async {
  final finder = find.text(text).at(index);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Enters text into a field, scrolling it into view first.
Future<void> fillField(WidgetTester tester, Finder field, String text) async {
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

void main() {
  group('dashboard', () {
    testWidgets('opens on the dashboard with the seeded ledger',
        (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.text('Ledger'), findsOneWidget);
      expect(find.text('Spent'), findsOneWidget);
      expect(find.text('Earned'), findsOneWidget);
      expect(find.text('Net worth'), findsOneWidget);
    });

    testWidgets('month navigation changes the subtitle', (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      final thisMonth = Period.of(DateTime.now());
      expect(find.text(thisMonth.label), findsWidgets);

      await tapText(tester, '← Previous');

      expect(find.text(thisMonth.previous.label), findsWidgets);
    });

    testWidgets('budget bars render for budgeted categories', (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.text('Budgets'), findsOneWidget);
      expect(find.byType(ProgressBar), findsWidgets);
    });
  });

  group('navigation', () {
    testWidgets('the FAB opens the new-transaction form', (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Proves /transactions/new beat /transactions/:id in the route table.
      expect(find.text('New transaction'), findsOneWidget);
    });

    testWidgets('reaches the transaction list and back', (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tapText(tester, 'See all transactions');
      expect(find.text('Transactions'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Ledger'), findsOneWidget);
    });

    testWidgets('an account row opens its detail screen by path',
        (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      final account = harness.repository.accounts.first;
      await tapText(tester, account.name);

      // /accounts/:id matched and passed the id through.
      expect(find.text('Balance'), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);
    });

    testWidgets('reaches categories and settings', (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tapText(tester, 'Categories');
      expect(find.text('Spending and budgets'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      expect(find.text('Security'), findsOneWidget);
    });
  });

  group('transaction list', () {
    testWidgets('search narrows the list', (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tapText(tester, 'See all transactions');

      await fillField(tester, find.byType(TextField).first, 'Rent');

      expect(find.textContaining('Rent'), findsWidgets);
      expect(find.text('Clear filters'), findsOneWidget);
    });

    testWidgets('a search matching nothing shows the empty state',
        (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tapText(tester, 'See all transactions');

      await fillField(tester, find.byType(TextField).first, 'zzzznothing');

      // A blank list would be indistinguishable from a broken query.
      expect(find.text('Nothing found'), findsOneWidget);
    });

    testWidgets('scrolling to the end loads another page', (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tapText(tester, 'See all transactions');

      expect(find.textContaining('Showing 20 of'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -1500));
      await tester.pumpAndSettle();

      // LazyColumn's onEndReached fired and TransactionsViewModel appended
      // the next page to the ones already on screen.
      expect(find.textContaining('Showing 40 of'), findsOneWidget);
    });
  });

  group('transaction form', () {
    testWidgets('saving with no amount shows a validation error',
        (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tapText(tester, 'Save');

      expect(find.text('Enter an amount'), findsOneWidget);
      expect(find.text('New transaction'), findsOneWidget,
          reason: 'an invalid save must not navigate away');
    });

    testWidgets('an invalid amount is reported as you type', (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tapText(tester, 'Save');

      await fillField(tester, find.byType(TextField).first, 'abc');

      // useTextField rebuilds the screen on every keystroke.
      expect(find.text('Not a valid amount'), findsOneWidget);
    });

    testWidgets('a saved transaction appears on the dashboard',
        (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      final spentBefore = harness.repository.spentIn(Period.of(DateTime.now()));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await fillField(tester, find.byType(TextField).first, '31.50');
      await fillField(tester, find.byType(TextField).last, 'Quixotic outing');

      await tapText(tester, 'Save');

      // Back on the dashboard, and its ViewModel refreshed via the repository
      // notification rather than being rebuilt from scratch.
      expect(find.text('Ledger'), findsOneWidget);
      expect(find.text('Quixotic outing'), findsOneWidget);
      expect(
        harness.repository.spentIn(Period.of(DateTime.now())).cents,
        spentBefore.cents + 3150,
      );
    });

    testWidgets('choosing Transfer hides the category picker', (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Category'), findsOneWidget);

      await tapText(tester, 'Transfer');

      // `if (form.needsCategory)` in the DSL compiled to a collection-if.
      expect(find.text('Category'), findsNothing);
    });

    testWidgets('editing an existing transaction prefills and updates',
        (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      final existing = harness.repository
          .query(TxQuery(period: Period.of(DateTime.now())), limit: 1)
          .items
          .first;

      await tapText(tester, existing.note);

      expect(find.text('Edit transaction'), findsOneWidget);
      expect(find.text(existing.amount.toEditString()), findsOneWidget);

      await fillField(tester, find.byType(TextField).first, '5.55');
      await tapText(tester, 'Save');

      expect(harness.repository.transaction(existing.id)!.amount.cents, 555);
    });
  });

  group('categories', () {
    testWidgets('setting a budget stores it', (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tapText(tester, 'Categories');

      await tapText(tester, 'Change budget');

      await fillField(tester, find.byType(TextField).first, '77.00');
      await tapText(tester, 'Save');

      expect(
        harness.repository.categories
            .any((c) => c.monthlyBudget?.cents == 7700),
        isTrue,
      );
    });
  });

  group('lock screen', () {
    testWidgets('a configured PIN sends the first frame to the lock screen',
        (tester) async {
      final harness = await boot(pin: '4821');
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.text('Enter your PIN'), findsOneWidget);
      expect(find.text('Ledger'), findsNothing);
    });

    testWidgets('the right PIN opens the ledger', (tester) async {
      final harness = await boot(pin: '4821');
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      for (final digit in ['4', '8', '2', '1']) {
        await tester.tap(find.widgetWithText(Button, digit));
        await tester.pump();
      }
      await tapText(tester, 'Unlock');

      expect(find.text('Spent'), findsOneWidget);
    });

    testWidgets('a wrong PIN reports the attempts left', (tester) async {
      final harness = await boot(pin: '4821');
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      for (final digit in ['0', '0', '0', '0']) {
        await tester.tap(find.widgetWithText(Button, digit));
        await tester.pump();
      }
      await tapText(tester, 'Unlock');

      expect(find.textContaining('attempts left'), findsOneWidget);
      expect(find.text('Enter your PIN'), findsOneWidget);
    });

    testWidgets('no PIN means the ledger opens straight away', (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.text('Enter your PIN'), findsNothing);
      expect(find.text('Spent'), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('dark mode toggles the theme', (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(
        Theme.of(tester.element(find.text('Security'))).brightness,
        Brightness.light,
      );

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // The app root is a Composable, so the theme follows the ViewModel.
      expect(
        Theme.of(tester.element(find.text('Security'))).brightness,
        Brightness.dark,
      );
    });

    testWidgets('mismatched PINs are rejected', (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await fillField(tester, fields.at(0), '4821');
      await fillField(tester, fields.at(1), '9999');

      await tapText(tester, 'Set PIN');

      expect(find.textContaining('do not match'), findsOneWidget);
      expect(harness.lock.isConfigured, isFalse);
    });
  });

  group('persistence', () {
    testWidgets('a transaction added in the UI survives a restart',
        (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await fillField(tester, find.byType(TextField).first, '12.34');
      await fillField(tester, find.byType(TextField).last, 'Persisted row');
      await tapText(tester, 'Save');

      // Rebuild the whole stack over the same storage, as a relaunch would.
      final reopened = LedgerRepository(harness.storage);
      await reopened.load();

      expect(
        reopened.query(const TxQuery(search: 'Persisted row')).total,
        1,
      );
    });
  });

  group('insights', () {
    testWidgets('object-push navigation reaches the screen and back',
        (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      // nav.to(InsightsScreen()) — pushed as an object, not through the route
      // table, so this exercises a different path from every other screen.
      await tapText(tester, 'Insights');
      expect(find.text('Across the last year'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Ledger'), findsOneWidget);
    });

    testWidgets('useFetch shows a spinner, then the report', (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Insights'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Insights'));

      // One frame in: the route is up but the report has not resolved, so the
      // generated AsyncValue.when is showing its loading branch.
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('At a glance'), findsOneWidget);
      expect(find.text('Last 12 months'), findsOneWidget);
      expect(find.text('Where it goes'), findsOneWidget);
    });

    testWidgets('the app bar survives the loading state', (tester) async {
      final harness = await boot();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Insights'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Insights'));
      await tester.pump();
      await tester.pump();

      // The fetch lives in a child composable, so .when replaces only that
      // subtree — the Screen's chrome stays put and you can still go back.
      // (Two AppBars are on screen mid-transition: the one being pushed and
      // the dashboard's, still animating out.)
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(AppBar), findsWidgets);
      expect(find.text('Across the last year'), findsOneWidget,
          reason: "the Insights app bar is up while the report is loading");

      // Let the fetch finish, or it is still pending at teardown.
      await tester.pumpAndSettle();
    });

    testWidgets('a failing fetch renders the error branch', (tester) async {
      final harness = await boot();
      // The injector is the seam: swap one provider, leave everything else.
      harness.injector.singleton<InsightsService>(
        (_) => _BrokenInsightsService(harness.repository),
      );

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await tapText(tester, 'Insights');

      expect(find.textContaining('Error:'), findsOneWidget);
      expect(find.textContaining('report unavailable'), findsOneWidget);
    });

    testWidgets('an empty ledger shows the empty state, not a blank page',
        (tester) async {
      final harness = await boot();
      for (final tx
          in harness.repository.query(const TxQuery(), limit: 1 << 30).items) {
        await harness.repository.deleteTransaction(tx.id);
      }

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await tapText(tester, 'Insights');

      expect(find.text('Nothing to report yet'), findsOneWidget);
    });
  });
}

/// Stands in for InsightsService to drive the error branch of useFetch.
class _BrokenInsightsService extends InsightsService {
  _BrokenInsightsService(super.repo);

  @override
  Future<InsightsReport> buildReport({int months = 12}) async =>
      throw StateError('report unavailable');
}
