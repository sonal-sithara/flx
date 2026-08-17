import 'package:flx_runtime/flx_runtime.dart';

import '../domain/models.dart';
import '../domain/money.dart';
import 'storage.dart';

/// Filters for a transaction query. All fields are optional and combine with
/// AND — an empty [TxQuery] matches everything.
class TxQuery {
  const TxQuery({
    this.search = '',
    this.accountId,
    this.categoryId,
    this.kind,
    this.period,
  });

  final String search;
  final String? accountId;
  final String? categoryId;
  final TxKind? kind;
  final Period? period;

  bool get isEmpty =>
      search.trim().isEmpty &&
      accountId == null &&
      categoryId == null &&
      kind == null &&
      period == null;

  TxQuery copyWith({
    String? search,
    String? accountId,
    String? categoryId,
    TxKind? kind,
    Period? period,
    bool clearAccount = false,
    bool clearCategory = false,
    bool clearKind = false,
    bool clearPeriod = false,
  }) =>
      TxQuery(
        search: search ?? this.search,
        accountId: clearAccount ? null : (accountId ?? this.accountId),
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        kind: clearKind ? null : (kind ?? this.kind),
        period: clearPeriod ? null : (period ?? this.period),
      );
}

/// One page of results plus enough information to ask for the next.
class TxPage {
  const TxPage({
    required this.items,
    required this.total,
    required this.offset,
  });

  final List<Transaction> items;

  /// Total matching the query, not the page size — drives "showing 20 of 431".
  final int total;
  final int offset;

  bool get hasMore => offset + items.length < total;
  int get nextOffset => offset + items.length;
}

/// Spend for one category within a period, against its budget.
class BudgetLine {
  const BudgetLine({
    required this.category,
    required this.spent,
    required this.budget,
  });

  final Category category;
  final Money spent;
  final Money? budget;

  bool get hasBudget => budget != null;
  bool get isOver => budget != null && spent > budget!;
  Money get remaining =>
      budget == null ? const Money.zero() : budget! - spent;

  /// 0..1 for the progress bar; 1.0 once the budget is blown.
  double get fraction => budget == null ? 0 : spent.fractionOf(budget!);
}

/// The single source of truth for ledger data.
///
/// Reads are synchronous against an in-memory cache so the UI never awaits;
/// writes update the cache and persist in the background. [load] must be
/// awaited once at startup.
///
/// It is a [Notifier]: every write announces itself, so a ViewModel that was
/// built for one screen still refreshes when another screen edits the data.
/// Without this, adding a transaction leaves the dashboard showing stale
/// totals until the app restarts.
class LedgerRepository extends Notifier {
  LedgerRepository(this._storage);

  static const _key = 'ledger.v1';

  final Storage _storage;

  final _accounts = <String, Account>{};
  final _categories = <String, Category>{};
  final _transactions = <String, Transaction>{};

  /// Monotonic counter behind generated ids, so two ids created in the same
  /// millisecond cannot collide.
  int _sequence = 0;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  // ------------------------------------------------------------- lifecycle

  Future<void> load() async {
    final json = await _storage.readJson(_key);
    if (json != null) {
      _restore(json);
    } else {
      _seedStarterData();
      await _persist();
    }
    _loaded = true;
  }

  void _restore(Map<String, Object?> json) {
    _accounts.clear();
    _categories.clear();
    _transactions.clear();

    for (final raw in (json['accounts'] as List? ?? const [])) {
      final account = Account.fromJson(raw as Map<String, Object?>);
      _accounts[account.id] = account;
    }
    for (final raw in (json['categories'] as List? ?? const [])) {
      final category = Category.fromJson(raw as Map<String, Object?>);
      _categories[category.id] = category;
    }
    for (final raw in (json['transactions'] as List? ?? const [])) {
      final tx = Transaction.fromJson(raw as Map<String, Object?>);
      _transactions[tx.id] = tx;
    }
    _sequence = (json['sequence'] as int?) ?? 0;
  }

  /// Persists and announces the change. Every mutation funnels through here,
  /// so this is the single place that has to remember to notify.
  Future<void> _persist() async {
    await _storage.writeJson(_key, {
      'sequence': _sequence,
      'accounts': _accounts.values.map((a) => a.toJson()).toList(),
      'categories': _categories.values.map((c) => c.toJson()).toList(),
      'transactions': _transactions.values.map((t) => t.toJson()).toList(),
    });
    notify();
  }

  String _nextId(String prefix) =>
      '$prefix-${DateTime.now().millisecondsSinceEpoch}-${_sequence++}';

  /// Wipes everything and reinstates the starter data.
  Future<void> reset() async {
    _accounts.clear();
    _categories.clear();
    _transactions.clear();
    _sequence = 0;
    _seedStarterData();
    await _persist();
  }

  // --------------------------------------------------------------- reading

  List<Account> get accounts => _accounts.values
      .where((a) => !a.archived)
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  List<Account> get allAccounts => _accounts.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  List<Category> get categories => _categories.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  Account? account(String id) => _accounts[id];
  Category? category(String id) => _categories[id];
  Transaction? transaction(String id) => _transactions[id];

  /// Opening balance plus every transaction against the account.
  Money balanceOf(String accountId) {
    final account = _accounts[accountId];
    if (account == null) return const Money.zero();
    var total = account.openingBalance;
    for (final tx in _transactions.values) {
      if (tx.accountId == accountId) total += tx.signedAmount;
    }
    return total;
  }

  /// Sum of every non-liability account, minus what is owed on credit.
  Money get netWorth {
    var total = const Money.zero();
    for (final account in _accounts.values) {
      if (account.archived) continue;
      final balance = balanceOf(account.id);
      total += account.kind.isLiability ? -balance : balance;
    }
    return total;
  }

  /// Matching transactions, newest first, as one page.
  TxPage query(TxQuery filter, {int offset = 0, int limit = 25}) {
    final matches = _transactions.values.where((tx) => _matches(tx, filter))
        .toList()
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        // Ties broken by id so pagination is stable across calls — otherwise
        // the same row can appear on two pages.
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });

    final start = offset.clamp(0, matches.length);
    final end = (offset + limit).clamp(0, matches.length);
    return TxPage(
      items: matches.sublist(start, end),
      total: matches.length,
      offset: start,
    );
  }

  bool _matches(Transaction tx, TxQuery filter) {
    if (filter.accountId != null && tx.accountId != filter.accountId) {
      return false;
    }
    if (filter.categoryId != null && tx.categoryId != filter.categoryId) {
      return false;
    }
    if (filter.kind != null && tx.kind != filter.kind) return false;
    if (filter.period != null && !filter.period!.contains(tx.date)) {
      return false;
    }

    final search = filter.search.trim().toLowerCase();
    if (search.isEmpty) return true;

    // Search covers the note, the category name and the amount as typed.
    if (tx.note.toLowerCase().contains(search)) return true;
    final categoryName = _categories[tx.categoryId]?.name.toLowerCase();
    if (categoryName != null && categoryName.contains(search)) return true;
    if (tx.amount.toEditString().contains(search)) return true;
    return false;
  }

  /// Total spend for [period], expenses only.
  Money spentIn(Period period) {
    var total = const Money.zero();
    for (final tx in _transactions.values) {
      if (tx.kind == TxKind.expense && period.contains(tx.date)) {
        total += tx.amount;
      }
    }
    return total;
  }

  Money earnedIn(Period period) {
    var total = const Money.zero();
    for (final tx in _transactions.values) {
      if (tx.kind == TxKind.income && period.contains(tx.date)) {
        total += tx.amount;
      }
    }
    return total;
  }

  /// Per-category spend for [period], budgeted categories first, then by
  /// spend descending.
  List<BudgetLine> budgetLines(Period period) {
    final spend = <String, Money>{};
    for (final tx in _transactions.values) {
      if (tx.kind != TxKind.expense || !period.contains(tx.date)) continue;
      spend[tx.categoryId] =
          (spend[tx.categoryId] ?? const Money.zero()) + tx.amount;
    }

    final lines = categories
        .map((c) => BudgetLine(
              category: c,
              spent: spend[c.id] ?? const Money.zero(),
              budget: c.monthlyBudget,
            ))
        .toList()
      ..sort((a, b) {
        if (a.hasBudget != b.hasBudget) return a.hasBudget ? -1 : 1;
        return b.spent.compareTo(a.spent);
      });
    return lines;
  }

  /// Periods that actually contain transactions, newest first. Drives the
  /// month picker so it never offers an empty month.
  List<Period> get activePeriods {
    final periods = <Period>{Period.of(DateTime.now())};
    for (final tx in _transactions.values) {
      periods.add(Period.of(tx.date));
    }
    return periods.toList()..sort((a, b) => b.compareTo(a));
  }

  // --------------------------------------------------------------- writing

  Future<Account> upsertAccount({
    String? id,
    required String name,
    required AccountKind kind,
    Money openingBalance = const Money.zero(),
  }) async {
    final account = Account(
      id: id ?? _nextId('acc'),
      name: name,
      kind: kind,
      openingBalance: openingBalance,
      archived: id == null ? false : (_accounts[id]?.archived ?? false),
    );
    _accounts[account.id] = account;
    await _persist();
    return account;
  }

  /// Archives rather than deletes — removing an account would orphan every
  /// transaction that points at it.
  Future<void> archiveAccount(String id) async {
    final account = _accounts[id];
    if (account == null) return;
    _accounts[id] = account.copyWith(archived: true);
    await _persist();
  }

  Future<Category> upsertCategory({
    String? id,
    required String name,
    required int colorValue,
    Money? monthlyBudget,
  }) async {
    final category = Category(
      id: id ?? _nextId('cat'),
      name: name,
      colorValue: colorValue,
      monthlyBudget: monthlyBudget,
    );
    _categories[category.id] = category;
    await _persist();
    return category;
  }

  Future<void> setBudget(String categoryId, Money? budget) async {
    final category = _categories[categoryId];
    if (category == null) return;
    _categories[categoryId] = Category(
      id: category.id,
      name: category.name,
      colorValue: category.colorValue,
      monthlyBudget: budget,
    );
    await _persist();
  }

  Future<Transaction> upsertTransaction({
    String? id,
    required String accountId,
    required String categoryId,
    required Money amount,
    required DateTime date,
    required TxKind kind,
    String note = '',
  }) async {
    final tx = Transaction(
      id: id ?? _nextId('tx'),
      accountId: accountId,
      categoryId: categoryId,
      amount: amount.abs,
      date: date,
      kind: kind,
      note: note,
    );
    _transactions[tx.id] = tx;
    await _persist();
    return tx;
  }

  Future<void> deleteTransaction(String id) async {
    _transactions.remove(id);
    await _persist();
  }

  // ----------------------------------------------------------------- seeds

  /// A brand new ledger is useless for judging the UI, so a first launch gets
  /// a realistic three months of history.
  void _seedStarterData() {
    final checking = Account(
      id: 'acc-checking',
      name: 'Everyday Checking',
      kind: AccountKind.checking,
      openingBalance: const Money(420000),
    );
    final savings = Account(
      id: 'acc-savings',
      name: 'Savings',
      kind: AccountKind.savings,
      openingBalance: const Money(1250000),
    );
    final card = Account(
      id: 'acc-card',
      name: 'Visa',
      kind: AccountKind.credit,
    );
    for (final a in [checking, savings, card]) {
      _accounts[a.id] = a;
    }

    const seedCategories = [
      ('cat-groceries', 'Groceries', 0xFF4CAF50, 60000),
      ('cat-rent', 'Rent', 0xFF3F51B5, 180000),
      ('cat-transport', 'Transport', 0xFFFF9800, 15000),
      ('cat-dining', 'Dining out', 0xFFE91E63, 25000),
      ('cat-utilities', 'Utilities', 0xFF009688, 12000),
      ('cat-fun', 'Entertainment', 0xFF9C27B0, null),
      ('cat-salary', 'Salary', 0xFF607D8B, null),
    ];
    for (final (id, name, color, budget) in seedCategories) {
      _categories[id] = Category(
        id: id,
        name: name,
        colorValue: color,
        monthlyBudget: budget == null ? null : Money(budget),
      );
    }

    // Deterministic pseudo-random so the seed looks varied but a failing test
    // can always be reproduced.
    var seed = 1337;
    int next(int max) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed % max;
    }

    final now = DateTime.now();
    for (var monthsAgo = 2; monthsAgo >= 0; monthsAgo--) {
      final anchor = DateTime(now.year, now.month - monthsAgo);

      /// A seeded timestamp inside this month, never in the future.
      ///
      /// The current month is only partly over. Spending that has not
      /// happened yet is wrong on its face, and — because "Recent" is sorted
      /// newest first — a future-dated seed also hides the transaction the
      /// user just entered.
      DateTime at(int proposedDay, int proposedHour) {
        final candidate =
            DateTime(anchor.year, anchor.month, proposedDay, proposedHour);
        if (!candidate.isAfter(now)) return candidate;
        // Land somewhere between the 1st of this month and a moment ago.
        final elapsed = now.difference(DateTime(now.year, now.month)).inMinutes;
        return DateTime(now.year, now.month)
            .add(Duration(minutes: elapsed <= 1 ? 0 : next(elapsed)));
      }

      _transactions['tx-salary-$monthsAgo'] = Transaction(
        id: 'tx-salary-$monthsAgo',
        accountId: checking.id,
        categoryId: 'cat-salary',
        amount: const Money(520000),
        date: at(1, 9),
        kind: TxKind.income,
        note: 'Monthly salary',
      );
      _transactions['tx-rent-$monthsAgo'] = Transaction(
        id: 'tx-rent-$monthsAgo',
        accountId: checking.id,
        categoryId: 'cat-rent',
        amount: const Money(180000),
        date: at(2, 9),
        kind: TxKind.expense,
        note: 'Rent',
      );

      const notes = {
        'cat-groceries': ['Supermarket', 'Corner shop', 'Farmers market'],
        'cat-transport': ['Bus pass', 'Fuel', 'Taxi'],
        'cat-dining': ['Lunch', 'Coffee', 'Dinner out'],
        'cat-utilities': ['Electricity', 'Internet', 'Water'],
        'cat-fun': ['Cinema', 'Books', 'Concert'],
      };

      for (var i = 0; i < 22; i++) {
        final categoryId = notes.keys.elementAt(next(notes.length));
        final options = notes[categoryId]!;
        final id = 'tx-$monthsAgo-$i';
        _transactions[id] = Transaction(
          id: id,
          accountId: next(3) == 0 ? card.id : checking.id,
          categoryId: categoryId,
          amount: Money(500 + next(9500)),
          date: at(1 + next(27), 9 + next(12)),
          kind: TxKind.expense,
          note: options[next(options.length)],
        );
      }
    }

    _transactions['tx-transfer-0'] = Transaction(
      id: 'tx-transfer-0',
      accountId: savings.id,
      categoryId: '',
      amount: const Money(50000),
      date: DateTime(now.year, now.month, 3),
      kind: TxKind.income,
      note: 'Transfer to savings',
    );

    _sequence = 100;
  }
}
