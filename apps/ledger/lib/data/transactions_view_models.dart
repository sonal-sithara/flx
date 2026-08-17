import 'package:flx_runtime/flx_runtime.dart';

import '../domain/models.dart';
import '../domain/money.dart';
import 'ledger_repository.dart';

/// The paginated, searchable transaction list.
///
/// Pages accumulate into [items] rather than replacing them, so scrolling
/// never loses what is already on screen.
class TransactionsViewModel extends ViewModel {
  TransactionsViewModel(this._repo) {
    _loadPage();
    // A transaction added on the form screen must show up here without the
    // list being rebuilt from scratch by the navigator.
    _repo.addListener(_onRepoChanged);
  }

  void _onRepoChanged() => _restart();

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    super.dispose();
  }

  static const pageSize = 20;

  final LedgerRepository _repo;

  final _items = <Transaction>[];
  TxQuery _query = const TxQuery();
  int _total = 0;
  bool _loading = false;

  List<Transaction> get items => List.unmodifiable(_items);
  TxQuery get query => _query;
  int get total => _total;
  int get loadedCount => _items.length;
  bool get isLoading => _loading;
  bool get hasMore => _items.length < _total;
  bool get isEmpty => _items.isEmpty && !_loading;
  bool get isFiltered => !_query.isEmpty;

  /// `Showing 20 of 431` — worth stating, because a filtered list that looks
  /// short is otherwise indistinguishable from a broken query.
  String get countLabel =>
      hasMore ? 'Showing ${_items.length} of $_total' : '$_total transactions';

  void _loadPage() {
    _loading = true;
    final page = _repo.query(_query, offset: _items.length, limit: pageSize);
    _items.addAll(page.items);
    _total = page.total;
    _loading = false;
    notify();
  }

  /// Fired by LazyColumn as the list nears its end. Scroll physics deliver
  /// many notifications per fling, so this must stay cheap and idempotent.
  void loadMore() {
    if (_loading || !hasMore) return;
    _loadPage();
  }

  void _restart() {
    _items.clear();
    _total = 0;
    _loadPage();
  }

  void refresh() => _restart();

  void setSearch(String value) {
    if (value == _query.search) return;
    _query = _query.copyWith(search: value);
    _restart();
  }

  void setKind(TxKind? kind) {
    _query = kind == null
        ? _query.copyWith(clearKind: true)
        : _query.copyWith(kind: kind);
    _restart();
  }

  void setAccount(String? accountId) {
    _query = accountId == null
        ? _query.copyWith(clearAccount: true)
        : _query.copyWith(accountId: accountId);
    _restart();
  }

  void setCategory(String? categoryId) {
    _query = categoryId == null
        ? _query.copyWith(clearCategory: true)
        : _query.copyWith(categoryId: categoryId);
    _restart();
  }

  void setPeriod(Period? period) {
    _query = period == null
        ? _query.copyWith(clearPeriod: true)
        : _query.copyWith(period: period);
    _restart();
  }

  void clearFilters() {
    _query = const TxQuery();
    _restart();
  }

  Future<void> delete(String id) async {
    await _repo.deleteTransaction(id);
    _restart();
  }

  // Lookups the rows need for display.
  String categoryName(Transaction tx) =>
      _repo.category(tx.categoryId)?.name ?? 'Uncategorised';

  int categoryColor(Transaction tx) =>
      _repo.category(tx.categoryId)?.colorValue ?? 0xFF9E9E9E;

  String accountName(Transaction tx) =>
      _repo.account(tx.accountId)?.name ?? 'Unknown account';

  List<Account> get accounts => _repo.accounts;
  List<Category> get categories => _repo.categories;
  List<Period> get periods => _repo.activePeriods;
}

/// Create/edit form state and validation.
///
/// Text lives in the screen's controllers; this holds the choices and decides
/// what is wrong. Errors stay hidden until the first save attempt, so a form
/// does not greet you in red.
class TransactionFormViewModel extends ViewModel {
  TransactionFormViewModel(this._repo);

  final LedgerRepository _repo;

  String? _editingId;
  TxKind _kind = TxKind.expense;
  String? _accountId;
  String? _categoryId;
  DateTime _date = DateTime.now();
  bool _submitted = false;
  bool _saving = false;

  String? get editingId => _editingId;
  bool get isEditing => _editingId != null;
  TxKind get kind => _kind;
  String? get accountId => _accountId;
  String? get categoryId => _categoryId;
  DateTime get date => _date;
  bool get isSaving => _saving;
  bool get showErrors => _submitted;

  String get title => isEditing ? 'Edit transaction' : 'New transaction';

  List<Account> get accounts => _repo.accounts;
  List<Category> get categories => _repo.categories;

  /// Transfers have no category, so the picker is hidden for them.
  bool get needsCategory => _kind != TxKind.transfer;

  /// Loads an existing transaction, or resets to a blank form when [id] is
  /// null or unknown.
  void start(String? id) {
    final existing = id == null ? null : _repo.transaction(id);
    _editingId = existing?.id;
    _kind = existing?.kind ?? TxKind.expense;
    _accountId = existing?.accountId ??
        (_repo.accounts.isEmpty ? null : _repo.accounts.first.id);
    _categoryId = existing?.categoryId.isEmpty ?? true
        ? (_repo.categories.isEmpty ? null : _repo.categories.first.id)
        : existing!.categoryId;
    _date = existing?.date ?? DateTime.now();
    _submitted = false;
    _saving = false;
    notify();
  }

  /// Prepares the form for [routeId] and returns itself, so a screen can hold
  /// it in a memoised `val` and have it run exactly once per id:
  ///
  ///   val form = useMemoized(() => vm.opened(id), [id])
  ///
  /// An empty id means "new transaction".
  TransactionFormViewModel opened(String routeId) {
    start(routeId.isEmpty ? null : routeId);
    return this;
  }

  /// The amount to prefill the text field with when editing.
  String initialAmountText(String? id) {
    final existing = id == null ? null : _repo.transaction(id);
    return existing == null ? '' : existing.amount.toEditString();
  }

  String initialNoteText(String? id) {
    final existing = id == null ? null : _repo.transaction(id);
    return existing?.note ?? '';
  }

  void setKind(TxKind value) {
    _kind = value;
    if (!needsCategory) _categoryId = null;
    if (needsCategory && _categoryId == null && _repo.categories.isNotEmpty) {
      _categoryId = _repo.categories.first.id;
    }
    notify();
  }

  void setAccount(String value) {
    _accountId = value;
    notify();
  }

  void setCategory(String value) {
    _categoryId = value;
    notify();
  }

  void setDate(DateTime value) {
    _date = value;
    notify();
  }

  // ------------------------------------------------------------ validation

  /// Null when valid. Called on every keystroke, so it stays pure.
  String? amountError(String text) {
    if (!_submitted && text.trim().isEmpty) return null;
    if (text.trim().isEmpty) return 'Enter an amount';

    final money = Money.tryParse(text);
    if (money == null) return 'Not a valid amount';
    if (money.isZero) return 'Amount cannot be zero';
    if (money.cents.abs() > 100000000) return 'That amount is too large';
    return null;
  }

  String? get accountError {
    if (!_submitted) return null;
    return _accountId == null ? 'Choose an account' : null;
  }

  String? get categoryError {
    if (!_submitted || !needsCategory) return null;
    return _categoryId == null ? 'Choose a category' : null;
  }

  String? dateError() {
    if (!_submitted) return null;
    // A far-future date is nearly always a typo in the year.
    final limit = DateTime.now().add(const Duration(days: 365));
    return _date.isAfter(limit) ? 'That date is more than a year away' : null;
  }

  bool isValid(String amountText) =>
      Money.tryParse(amountText) != null &&
      !(Money.tryParse(amountText)!.isZero) &&
      _accountId != null &&
      (!needsCategory || _categoryId != null);

  /// Attempts to save. Returns true when the transaction was written.
  Future<bool> save({required String amountText, required String note}) async {
    _submitted = true;
    notify();

    if (!isValid(amountText)) return false;

    _saving = true;
    notify();

    await _repo.upsertTransaction(
      id: _editingId,
      accountId: _accountId!,
      categoryId: needsCategory ? _categoryId! : '',
      amount: Money.tryParse(amountText)!,
      date: _date,
      kind: _kind,
      note: note.trim(),
    );

    _saving = false;
    notify();
    return true;
  }

  Future<void> delete() async {
    final id = _editingId;
    if (id == null) return;
    await _repo.deleteTransaction(id);
  }
}
