import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/insights.dart';
import 'package:ledger/data/ledger_repository.dart';
import 'package:ledger/data/storage.dart';
import 'package:ledger/domain/models.dart';
import 'package:ledger/domain/money.dart';

Future<LedgerRepository> freshRepo([MemoryStorage? storage]) async {
  final repo = LedgerRepository(storage ?? MemoryStorage());
  await repo.load();
  return repo;
}

/// A repository with no transactions at all.
Future<LedgerRepository> emptyRepo() async {
  final repo = await freshRepo();
  for (final tx in repo.query(const TxQuery(), limit: 1 << 30).items) {
    await repo.deleteTransaction(tx.id);
  }
  return repo;
}

void main() {
  group('buildReport', () {
    test('is genuinely asynchronous', () async {
      final service = InsightsService(await freshRepo());
      var resolved = false;

      final future = service.buildReport().then((_) => resolved = true);

      // The screen must get a loading frame, so this must not complete in the
      // same microtask it was started in.
      expect(resolved, isFalse);
      await future;
      expect(resolved, isTrue);
    });

    test('returns one trend entry per requested month, oldest first',
        () async {
      final service = InsightsService(await freshRepo());
      final report = await service.buildReport(months: 12);

      expect(report.trend.length, 12);
      for (var i = 1; i < report.trend.length; i++) {
        expect(
          report.trend[i - 1].period.compareTo(report.trend[i].period),
          lessThan(0),
          reason: 'the trend should read left to right',
        );
      }
      expect(report.trend.last.period, Period.of(DateTime.now()));
    });

    test('counts only transactions inside the window', () async {
      final repo = await freshRepo();
      final service = InsightsService(repo);

      final all = repo.query(const TxQuery(), limit: 1 << 30).total;
      final report = await service.buildReport(months: 12);

      // The seed spans three months, so a twelve-month window holds all of it.
      expect(report.transactionCount, all);

      final narrow = await service.buildReport(months: 1);
      expect(narrow.transactionCount, lessThan(all));
      expect(narrow.trend.length, 1);
    });

    test('breakdown shares sum to one and are sorted by spend', () async {
      final report = await InsightsService(await freshRepo()).buildReport();

      expect(report.breakdown, isNotEmpty);
      for (var i = 1; i < report.breakdown.length; i++) {
        expect(
          report.breakdown[i - 1].spent >= report.breakdown[i].spent,
          isTrue,
        );
      }

      final total = report.breakdown.fold<double>(0, (sum, s) => sum + s.share);
      expect(total, closeTo(1.0, 0.001));
    });

    test('breakdown covers expenses only', () async {
      final repo = await freshRepo();
      final report = await InsightsService(repo).buildReport();

      // Salary is income, so it must not appear as somewhere money "goes".
      expect(
        report.breakdown.any((s) => s.category.name == 'Salary'),
        isFalse,
      );
    });

    test('averages over active months, not the whole window', () async {
      final repo = await freshRepo();
      final report = await InsightsService(repo).buildReport(months: 12);

      final active = report.trend.where((m) => !m.spent.isZero).length;
      expect(active, lessThan(12), reason: 'the seed only spans three months');

      var total = const Money.zero();
      for (final month in report.trend) {
        total += month.spent;
      }
      // Dividing by twelve would understate a three-month-old ledger badly.
      expect(report.averageMonthlySpend.cents, total.cents ~/ active);
    });

    test('identifies the busiest month and largest expense', () async {
      final repo = await freshRepo();
      final marker = await repo.upsertTransaction(
        accountId: repo.accounts.first.id,
        categoryId: repo.categories.first.id,
        amount: const Money(9999999),
        date: DateTime.now(),
        kind: TxKind.expense,
        note: 'Unmistakably the largest',
      );

      final report = await InsightsService(repo).buildReport();

      expect(report.largestExpense?.id, marker.id);
      expect(report.busiestMonth, Period.of(DateTime.now()));
    });

    test('an empty ledger reports empty rather than dividing by zero',
        () async {
      final report = await InsightsService(await emptyRepo()).buildReport();

      expect(report.isEmpty, isTrue);
      expect(report.transactionCount, 0);
      expect(report.averageMonthlySpend, const Money.zero());
      expect(report.busiestMonth, isNull);
      expect(report.largestExpense, isNull);
      expect(report.breakdown, isEmpty);
      expect(report.peakSpend, const Money.zero());
    });

    test('bar heights scale against the peak without overflowing', () async {
      final report = await InsightsService(await freshRepo()).buildReport();
      final peak = report.peakSpend;

      for (final month in report.trend) {
        final height = month.heightAgainst(peak);
        expect(height, inInclusiveRange(0.0, 1.0));
      }
      expect(
        report.trend.map((m) => m.heightAgainst(peak)).reduce((a, b) => a > b ? a : b),
        1.0,
        reason: 'the tallest month should fill the bar',
      );
    });
  });
}
