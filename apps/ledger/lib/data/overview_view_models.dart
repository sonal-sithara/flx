import 'package:flx/flx.dart';

import '../domain/models.dart';
import '../domain/money.dart';
import 'ledger_repository.dart';

/// The dashboard: one month at a time, with totals, budgets and recent rows.
class DashboardViewModel extends ViewModel {
  DashboardViewModel(this._repo) : _period = Period.of(DateTime.now()) {
    _repo.addListener(refresh);
  }

  final LedgerRepository _repo;
  Period _period;

  @override
  void dispose() {
    _repo.removeListener(refresh);
    super.dispose();
  }

  Period get period => _period;
  String get periodLabel => _period.label;

  Money get spent => _repo.spentIn(_period);
  Money get earned => _repo.earnedIn(_period);
  Money get net => earned - spent;
  Money get netWorth => _repo.netWorth;

  bool get isOverspending => net.isNegative;

  List<BudgetLine> get budgets =>
      _repo.budgetLines(_period).where((line) => line.hasBudget).toList();

  /// Categories with spend but no budget — a nudge to set one.
  List<BudgetLine> get unbudgeted => _repo
      .budgetLines(_period)
      .where((line) => !line.hasBudget && !line.spent.isZero)
      .toList();

  List<Transaction> get recent =>
      _repo.query(TxQuery(period: _period), limit: 5).items;

  List<Account> get accounts => _repo.accounts;

  Money balanceOf(String accountId) => _repo.balanceOf(accountId);

  String categoryName(Transaction tx) =>
      _repo.category(tx.categoryId)?.name ?? 'Uncategorised';

  int categoryColor(Transaction tx) =>
      _repo.category(tx.categoryId)?.colorValue ?? 0xFF9E9E9E;

  /// The months that actually have data, newest first.
  List<Period> get periods => _repo.activePeriods;

  bool get hasAnything => !spent.isZero || !earned.isZero;

  /// Total budgeted across every category with a budget.
  Money get totalBudget {
    var total = const Money.zero();
    for (final line in budgets) {
      total += line.budget!;
    }
    return total;
  }

  /// Spend against the total budget, 0..1.
  double get budgetFraction {
    final total = totalBudget;
    if (total.isZero) return 0;
    var used = const Money.zero();
    for (final line in budgets) {
      used += line.spent;
    }
    return used.fractionOf(total);
  }

  void setPeriod(Period value) {
    _period = value;
    notify();
  }

  void previousMonth() {
    _period = _period.previous;
    notify();
  }

  void nextMonth() {
    _period = _period.next;
    notify();
  }

  /// Recomputes after a write elsewhere in the app.
  void refresh() => notify();
}

/// Accounts list and the per-account detail view.
class AccountsViewModel extends ViewModel {
  AccountsViewModel(this._repo) {
    _repo.addListener(notify);
  }

  final LedgerRepository _repo;

  @override
  void dispose() {
    _repo.removeListener(notify);
    super.dispose();
  }

  String? _nameError;
  bool _submitted = false;

  String? get nameError => _nameError;

  List<Account> get accounts => _repo.accounts;
  Money get netWorth => _repo.netWorth;

  Account? account(String id) => _repo.account(id);
  Money balanceOf(String id) => _repo.balanceOf(id);

  String balanceLabel(Account account) {
    final balance = _repo.balanceOf(account.id);
    return account.kind.isLiability && !balance.isZero
        ? '${(-balance).format()} owed'
        : balance.format();
  }

  /// The account's own transactions, newest first.
  List<Transaction> transactionsFor(String accountId, {int limit = 50}) =>
      _repo.query(TxQuery(accountId: accountId), limit: limit).items;

  int transactionCount(String accountId) =>
      _repo.query(TxQuery(accountId: accountId), limit: 0).total;

  String categoryName(Transaction tx) =>
      _repo.category(tx.categoryId)?.name ?? 'Uncategorised';

  Future<bool> addAccount(String name, AccountKind kind, String opening) async {
    _submitted = true;
    if (name.trim().isEmpty) {
      _nameError = 'Give the account a name';
      notify();
      return false;
    }
    final duplicate = _repo.accounts
        .any((a) => a.name.toLowerCase() == name.trim().toLowerCase());
    if (duplicate) {
      _nameError = 'An account with that name already exists';
      notify();
      return false;
    }

    _nameError = null;
    await _repo.upsertAccount(
      name: name.trim(),
      kind: kind,
      openingBalance: Money.tryParse(opening) ?? const Money.zero(),
    );
    _submitted = false;
    notify();
    return true;
  }

  Future<void> archive(String id) async {
    await _repo.archiveAccount(id);
    notify();
  }

  void resetForm() {
    _submitted = false;
    _nameError = null;
    notify();
  }

  bool get showErrors => _submitted;
}

/// Categories and their monthly budgets.
class CategoriesViewModel extends ViewModel {
  CategoriesViewModel(this._repo) : _period = Period.of(DateTime.now()) {
    _repo.addListener(notify);
  }

  final LedgerRepository _repo;
  Period _period;

  @override
  void dispose() {
    _repo.removeListener(notify);
    super.dispose();
  }

  String? _editingId;
  String? _budgetError;

  Period get period => _period;
  String get periodLabel => _period.label;
  String? get editingId => _editingId;
  String? get budgetError => _budgetError;

  List<BudgetLine> get lines => _repo.budgetLines(_period);

  int get overBudgetCount => lines.where((l) => l.isOver).length;

  String budgetLabel(BudgetLine line) => line.hasBudget
      ? '${line.spent.format()} of ${line.budget!.format()}'
      : line.spent.format();

  /// Opens the inline budget editor for one category.
  void startEditing(String categoryId) {
    _editingId = categoryId;
    _budgetError = null;
    notify();
  }

  void cancelEditing() {
    _editingId = null;
    _budgetError = null;
    notify();
  }

  String initialBudgetText(String categoryId) =>
      _repo.category(categoryId)?.monthlyBudget?.toEditString() ?? '';

  /// Empty text clears the budget; anything unparseable is an error.
  Future<bool> saveBudget(String categoryId, String text) async {
    if (text.trim().isEmpty) {
      await _repo.setBudget(categoryId, null);
      _editingId = null;
      _budgetError = null;
      notify();
      return true;
    }

    final money = Money.tryParse(text);
    if (money == null || money.isNegative) {
      _budgetError = 'Enter a positive amount, or leave blank for no budget';
      notify();
      return false;
    }

    await _repo.setBudget(categoryId, money);
    _editingId = null;
    _budgetError = null;
    notify();
    return true;
  }

  Future<bool> addCategory(String name, int colorValue) async {
    if (name.trim().isEmpty) return false;
    await _repo.upsertCategory(name: name.trim(), colorValue: colorValue);
    notify();
    return true;
  }

  void setPeriod(Period value) {
    _period = value;
    notify();
  }
}
