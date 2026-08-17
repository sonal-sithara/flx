import '../domain/models.dart';
import '../domain/money.dart';
import 'ledger_repository.dart';

/// Spend and income for one month of the trend.
class MonthlyTotal {
  const MonthlyTotal({
    required this.period,
    required this.spent,
    required this.earned,
  });

  final Period period;
  final Money spent;
  final Money earned;

  Money get net => earned - spent;

  /// Height of this bar relative to the tallest month, 0..1.
  double heightAgainst(Money peak) => spent.fractionOf(peak);
}

/// One category's share of total spend across the report window.
class CategoryShare {
  const CategoryShare({
    required this.category,
    required this.spent,
    required this.share,
  });

  final Category category;
  final Money spent;

  /// 0..1 of total spend.
  final double share;

  String get percentLabel => '${(share * 100).round()}%';
}

class InsightsReport {
  const InsightsReport({
    required this.trend,
    required this.breakdown,
    required this.averageMonthlySpend,
    required this.busiestMonth,
    required this.largestExpense,
    required this.transactionCount,
  });

  /// Oldest first, so it reads left to right as a chart.
  final List<MonthlyTotal> trend;

  /// Largest share first.
  final List<CategoryShare> breakdown;

  final Money averageMonthlySpend;
  final Period? busiestMonth;
  final Transaction? largestExpense;
  final int transactionCount;

  bool get isEmpty => transactionCount == 0;

  /// The tallest bar, used to scale the rest.
  Money get peakSpend => trend.isEmpty
      ? const Money.zero()
      : trend.map((m) => m.spent).reduce((a, b) => a > b ? a : b);
}

/// Builds the insights report.
///
/// This is the one genuinely asynchronous read in the app: it walks every
/// transaction several times over a twelve-month window, which is real work
/// once a ledger has a few thousand rows and does not belong on the path of a
/// widget build. Everything else reads from the repository's in-memory cache
/// synchronously.
///
/// The `await` below is also the seam where this moves to `compute()` and a
/// background isolate — the screen already treats it as async, so that change
/// would not touch the UI at all.
class InsightsService {
  InsightsService(this._repo);

  final LedgerRepository _repo;

  Future<InsightsReport> buildReport({int months = 12}) async {
    // Yield first, so the caller always sees a loading state rather than the
    // report appearing to materialise synchronously on some devices and not
    // others.
    await Future<void>.delayed(Duration.zero);

    final periods = _recentPeriods(months);
    final trend = <MonthlyTotal>[];
    for (final period in periods) {
      trend.add(MonthlyTotal(
        period: period,
        spent: _repo.spentIn(period),
        earned: _repo.earnedIn(period),
      ));
    }

    final window = _repo.query(
      const TxQuery(),
      limit: 1 << 30,
    ).items.where((tx) => periods.any((p) => p.contains(tx.date))).toList();

    final expenses = window.where((tx) => tx.kind == TxKind.expense).toList();

    return InsightsReport(
      trend: trend,
      breakdown: _breakdown(expenses),
      averageMonthlySpend: _averageSpend(trend),
      busiestMonth: _busiestMonth(trend),
      largestExpense: _largestExpense(expenses),
      transactionCount: window.length,
    );
  }

  /// [months] periods ending with the current one, oldest first.
  List<Period> _recentPeriods(int months) {
    var period = Period.of(DateTime.now());
    final periods = <Period>[];
    for (var i = 0; i < months; i++) {
      periods.add(period);
      period = period.previous;
    }
    return periods.reversed.toList();
  }

  List<CategoryShare> _breakdown(List<Transaction> expenses) {
    final totals = <String, Money>{};
    var overall = const Money.zero();
    for (final tx in expenses) {
      totals[tx.categoryId] =
          (totals[tx.categoryId] ?? const Money.zero()) + tx.amount;
      overall += tx.amount;
    }

    final shares = <CategoryShare>[];
    for (final entry in totals.entries) {
      final category = _repo.category(entry.key);
      if (category == null) continue;
      shares.add(CategoryShare(
        category: category,
        spent: entry.value,
        share: entry.value.fractionOf(overall),
      ));
    }
    shares.sort((a, b) => b.spent.compareTo(a.spent));
    return shares;
  }

  /// Averaged over months that actually had spending — dividing by twelve on
  /// a ledger three months old would report a figure that is simply wrong.
  Money _averageSpend(List<MonthlyTotal> trend) {
    final active = trend.where((m) => !m.spent.isZero).toList();
    if (active.isEmpty) return const Money.zero();
    var total = const Money.zero();
    for (final month in active) {
      total += month.spent;
    }
    return Money(total.cents ~/ active.length);
  }

  Period? _busiestMonth(List<MonthlyTotal> trend) {
    MonthlyTotal? peak;
    for (final month in trend) {
      if (month.spent.isZero) continue;
      if (peak == null || month.spent > peak.spent) peak = month;
    }
    return peak?.period;
  }

  Transaction? _largestExpense(List<Transaction> expenses) {
    Transaction? largest;
    for (final tx in expenses) {
      if (largest == null || tx.amount > largest.amount) largest = tx;
    }
    return largest;
  }
}
