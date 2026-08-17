import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/ledger_repository.dart';
import 'package:ledger/data/overview_view_models.dart';
import 'package:ledger/data/security.dart';
import 'package:ledger/data/session_view_models.dart';
import 'package:ledger/data/storage.dart';
import 'package:ledger/data/transactions_view_models.dart';
import 'package:ledger/domain/models.dart';
import 'package:ledger/domain/money.dart';

Future<LedgerRepository> freshRepo([MemoryStorage? storage]) async {
  final repo = LedgerRepository(storage ?? MemoryStorage());
  await repo.load();
  return repo;
}

void main() {
  group('TransactionsViewModel', () {
    test('starts with one page loaded', () async {
      final vm = TransactionsViewModel(await freshRepo());

      expect(vm.items.length, TransactionsViewModel.pageSize);
      expect(vm.hasMore, isTrue);
      expect(vm.total, greaterThan(vm.items.length));
    });

    test('loadMore appends without duplicating', () async {
      final vm = TransactionsViewModel(await freshRepo());
      final firstPage = vm.items.map((t) => t.id).toList();

      vm.loadMore();

      expect(vm.items.length, TransactionsViewModel.pageSize * 2);
      expect(vm.items.map((t) => t.id).toSet().length, vm.items.length);
      expect(vm.items.take(firstPage.length).map((t) => t.id), firstPage);
    });

    test('loadMore is a no-op once everything is loaded', () async {
      final vm = TransactionsViewModel(await freshRepo());
      while (vm.hasMore) {
        vm.loadMore();
      }
      final settled = vm.items.length;

      // LazyColumn fires this repeatedly during a fling.
      vm.loadMore();
      vm.loadMore();

      expect(vm.items.length, settled);
      expect(vm.total, settled);
    });

    test('search restarts pagination from the top', () async {
      final vm = TransactionsViewModel(await freshRepo());
      vm.loadMore();
      expect(vm.items.length, greaterThan(TransactionsViewModel.pageSize));

      vm.setSearch('rent');

      expect(vm.items.length, lessThanOrEqualTo(TransactionsViewModel.pageSize));
      expect(vm.isFiltered, isTrue);
      for (final tx in vm.items) {
        expect(
          tx.note.toLowerCase().contains('rent') ||
              vm.categoryName(tx).toLowerCase().contains('rent'),
          isTrue,
        );
      }
    });

    test('clearFilters restores the full list', () async {
      final vm = TransactionsViewModel(await freshRepo());
      final total = vm.total;

      vm.setSearch('rent');
      expect(vm.total, lessThan(total));

      vm.clearFilters();
      expect(vm.total, total);
      expect(vm.isFiltered, isFalse);
    });

    test('setting the same search twice does not restart', () async {
      final vm = TransactionsViewModel(await freshRepo());
      vm.setSearch('rent');
      vm.loadMore();
      final loaded = vm.items.length;

      vm.setSearch('rent');
      expect(vm.items.length, loaded);
    });

    test('countLabel reflects whether more is pending', () async {
      final vm = TransactionsViewModel(await freshRepo());
      expect(vm.countLabel, startsWith('Showing '));

      vm.setSearch('a string that matches nothing at all');
      expect(vm.countLabel, '0 transactions');
    });

    test('rebuilds when the repository changes underneath it', () async {
      final repo = await freshRepo();
      final vm = TransactionsViewModel(repo);
      var notifications = 0;
      vm.addListener(() => notifications++);
      final before = vm.total;

      // Simulates the form screen saving a transaction.
      await repo.upsertTransaction(
        accountId: repo.accounts.first.id,
        categoryId: repo.categories.first.id,
        amount: const Money(4200),
        date: DateTime.now(),
        kind: TxKind.expense,
        note: 'From elsewhere',
      );

      expect(vm.total, before + 1);
      expect(notifications, greaterThan(0));
    });
  });

  group('TransactionFormViewModel', () {
    test('a new form defaults to an expense on the first account', () async {
      final repo = await freshRepo();
      final vm = TransactionFormViewModel(repo)..opened('');

      expect(vm.isEditing, isFalse);
      expect(vm.kind, TxKind.expense);
      expect(vm.accountId, repo.accounts.first.id);
      expect(vm.needsCategory, isTrue);
      expect(vm.title, 'New transaction');
    });

    test('opening an existing transaction loads its values', () async {
      final repo = await freshRepo();
      final existing = repo.query(const TxQuery()).items.first;
      final vm = TransactionFormViewModel(repo)..opened(existing.id);

      expect(vm.isEditing, isTrue);
      expect(vm.accountId, existing.accountId);
      expect(vm.kind, existing.kind);
      expect(vm.date, existing.date);
      expect(vm.initialAmountText(existing.id), existing.amount.toEditString());
      expect(vm.title, 'Edit transaction');
    });

    test('errors stay hidden until the first save attempt', () async {
      final vm = TransactionFormViewModel(await freshRepo())..opened('');

      expect(vm.amountError(''), isNull, reason: 'do not greet the user in red');
      expect(vm.accountError, isNull);

      final saved = await vm.save(amountText: '', note: '');

      expect(saved, isFalse);
      expect(vm.amountError(''), 'Enter an amount');
    });

    test('rejects unparseable, zero and absurd amounts', () async {
      final vm = TransactionFormViewModel(await freshRepo())..opened('');
      await vm.save(amountText: '', note: '');

      expect(vm.amountError('abc'), 'Not a valid amount');
      expect(vm.amountError('0'), 'Amount cannot be zero');
      expect(vm.amountError('99999999'), 'That amount is too large');
      expect(vm.amountError('12.34'), isNull);
    });

    test('transfers need no category', () async {
      final vm = TransactionFormViewModel(await freshRepo())..opened('');

      vm.setKind(TxKind.transfer);
      expect(vm.needsCategory, isFalse);
      expect(vm.categoryError, isNull);

      vm.setKind(TxKind.expense);
      expect(vm.needsCategory, isTrue);
      expect(vm.categoryId, isNotNull,
          reason: 'switching back should restore a default category');
    });

    test('a valid save writes to the repository', () async {
      final repo = await freshRepo();
      final vm = TransactionFormViewModel(repo)..opened('');
      final before = repo.query(const TxQuery()).total;

      // A note the seed data cannot also contain, so the search below can
      // only match the row this test wrote.
      final saved = await vm.save(amountText: '42.50', note: '  Quixotic  ');

      expect(saved, isTrue);
      expect(repo.query(const TxQuery()).total, before + 1);

      final written = repo.query(const TxQuery(search: 'Quixotic')).items.first;
      expect(written.amount.cents, 4250);
      expect(written.note, 'Quixotic', reason: 'the note should be trimmed');
    });

    test('editing updates in place rather than adding a row', () async {
      final repo = await freshRepo();
      final existing = repo.query(const TxQuery()).items.first;
      final before = repo.query(const TxQuery()).total;

      final vm = TransactionFormViewModel(repo)..opened(existing.id);
      await vm.save(amountText: '7.77', note: 'Edited');

      expect(repo.query(const TxQuery()).total, before);
      expect(repo.transaction(existing.id)!.amount.cents, 777);
      expect(repo.transaction(existing.id)!.note, 'Edited');
    });

    test('delete removes the edited transaction', () async {
      final repo = await freshRepo();
      final existing = repo.query(const TxQuery()).items.first;
      final vm = TransactionFormViewModel(repo)..opened(existing.id);

      await vm.delete();

      expect(repo.transaction(existing.id), isNull);
    });
  });

  group('DashboardViewModel', () {
    test('net is earned minus spent for the period', () async {
      final vm = DashboardViewModel(await freshRepo());
      expect(vm.net.cents, vm.earned.cents - vm.spent.cents);
    });

    test('month navigation moves the period', () async {
      final vm = DashboardViewModel(await freshRepo());
      final start = vm.period;

      vm.previousMonth();
      expect(vm.period, start.previous);

      vm.nextMonth();
      expect(vm.period, start);
    });

    test('only budgeted categories appear in budgets', () async {
      final vm = DashboardViewModel(await freshRepo());
      for (final line in vm.budgets) {
        expect(line.hasBudget, isTrue);
      }
      for (final line in vm.unbudgeted) {
        expect(line.hasBudget, isFalse);
        expect(line.spent.isZero, isFalse);
      }
    });

    test('recent is capped and newest first', () async {
      final vm = DashboardViewModel(await freshRepo());
      expect(vm.recent.length, lessThanOrEqualTo(5));
      for (var i = 1; i < vm.recent.length; i++) {
        expect(vm.recent[i - 1].date.isBefore(vm.recent[i].date), isFalse);
      }
    });

    test('refreshes when another screen writes', () async {
      final repo = await freshRepo();
      final vm = DashboardViewModel(repo);
      var notifications = 0;
      vm.addListener(() => notifications++);

      final before = vm.spent;
      await repo.upsertTransaction(
        accountId: repo.accounts.first.id,
        categoryId: repo.categories.first.id,
        amount: const Money(3300),
        date: DateTime.now(),
        kind: TxKind.expense,
      );

      expect(vm.spent.cents, before.cents + 3300);
      expect(notifications, greaterThan(0));
    });

    test('budgetFraction is zero when nothing is budgeted', () async {
      final repo = await freshRepo();
      for (final category in repo.categories) {
        await repo.setBudget(category.id, null);
      }
      final vm = DashboardViewModel(repo);

      expect(vm.totalBudget.isZero, isTrue);
      expect(vm.budgetFraction, 0);
    });
  });

  group('AccountsViewModel', () {
    test('rejects an empty or duplicate name', () async {
      final repo = await freshRepo();
      final vm = AccountsViewModel(repo);

      expect(await vm.addAccount('', AccountKind.cash, ''), isFalse);
      expect(vm.nameError, 'Give the account a name');

      final existing = repo.accounts.first.name;
      expect(await vm.addAccount(existing, AccountKind.cash, ''), isFalse);
      expect(vm.nameError, contains('already exists'));
    });

    test('duplicate detection ignores case and padding', () async {
      final repo = await freshRepo();
      final vm = AccountsViewModel(repo);
      final existing = repo.accounts.first.name;

      expect(
        await vm.addAccount('  ${existing.toUpperCase()}  ',
            AccountKind.cash, ''),
        isFalse,
      );
    });

    test('adds an account with a parsed opening balance', () async {
      final repo = await freshRepo();
      final vm = AccountsViewModel(repo);

      expect(await vm.addAccount('Holiday Fund', AccountKind.savings, '250.75'),
          isTrue);

      final added = repo.accounts.firstWhere((a) => a.name == 'Holiday Fund');
      expect(added.openingBalance.cents, 25075);
      expect(vm.nameError, isNull);
    });

    test('an unparseable opening balance falls back to zero', () async {
      final repo = await freshRepo();
      final vm = AccountsViewModel(repo);

      await vm.addAccount('Odd', AccountKind.cash, 'not a number');
      expect(
        repo.accounts.firstWhere((a) => a.name == 'Odd').openingBalance.isZero,
        isTrue,
      );
    });

    test('credit balances are labelled as owed', () async {
      final repo = await freshRepo();
      final vm = AccountsViewModel(repo);
      final card = await repo.upsertAccount(
        name: 'Owed Card',
        kind: AccountKind.credit,
        openingBalance: const Money(-15000),
      );

      expect(vm.balanceLabel(repo.account(card.id)!), r'$150.00 owed');
    });
  });

  group('CategoriesViewModel', () {
    test('an empty budget clears it', () async {
      final repo = await freshRepo();
      final vm = CategoriesViewModel(repo);
      final category = repo.categories.firstWhere((c) => c.hasBudget);

      expect(await vm.saveBudget(category.id, '   '), isTrue);
      expect(repo.category(category.id)!.monthlyBudget, isNull);
    });

    test('a negative or unparseable budget is rejected', () async {
      final repo = await freshRepo();
      final vm = CategoriesViewModel(repo);
      final category = repo.categories.first;

      expect(await vm.saveBudget(category.id, 'abc'), isFalse);
      expect(vm.budgetError, isNotNull);

      expect(await vm.saveBudget(category.id, '-50'), isFalse);
    });

    test('a valid budget is stored and closes the editor', () async {
      final repo = await freshRepo();
      final vm = CategoriesViewModel(repo)
        ..startEditing(repo.categories.first.id);
      expect(vm.editingId, isNotNull);

      expect(await vm.saveBudget(repo.categories.first.id, '125.50'), isTrue);

      expect(repo.category(repo.categories.first.id)!.monthlyBudget!.cents,
          12550);
      expect(vm.editingId, isNull);
    });

    test('overBudgetCount counts only categories past their budget', () async {
      final repo = await freshRepo();
      final vm = CategoriesViewModel(repo);
      final category = repo.categories.first;

      await repo.setBudget(category.id, const Money(1));
      await repo.upsertTransaction(
        accountId: repo.accounts.first.id,
        categoryId: category.id,
        amount: const Money(50000),
        date: DateTime.now(),
        kind: TxKind.expense,
      );

      expect(vm.overBudgetCount, greaterThan(0));
    });
  });

  group('LockViewModel', () {
    Future<(PinLock, LockViewModel)> lockWithPin(String pin) async {
      final lock = PinLock(MemoryStorage());
      await lock.load();
      await lock.setPin(pin);
      return (lock, LockViewModel(lock));
    }

    test('no PIN configured means no unlock needed', () async {
      final lock = PinLock(MemoryStorage());
      await lock.load();
      final vm = LockViewModel(lock);

      expect(vm.isConfigured, isFalse);
      expect(vm.requiresUnlock, isFalse);
    });

    test('the correct PIN unlocks', () async {
      final (_, vm) = await lockWithPin('1234');
      expect(vm.requiresUnlock, isTrue);

      for (final digit in ['1', '2', '3', '4']) {
        vm.press(digit);
      }
      expect(vm.entryLength, 4);
      expect(vm.submit(), isTrue);
      expect(vm.isUnlocked, isTrue);
      expect(vm.requiresUnlock, isFalse);
    });

    test('a wrong PIN clears the entry and counts down', () async {
      final (_, vm) = await lockWithPin('1234');

      vm..press('9')..press('9')..press('9')..press('9');
      expect(vm.submit(), isFalse);

      expect(vm.entryLength, 0, reason: 'the entry should reset');
      expect(vm.message, contains('attempts left'));
      expect(vm.isUnlocked, isFalse);
    });

    test('too many attempts locks out and stops accepting the right PIN',
        () async {
      final (_, vm) = await lockWithPin('1234');

      for (var attempt = 0; attempt < PinLock.maxAttempts; attempt++) {
        vm..press('0')..press('0')..press('0')..press('0');
        vm.submit();
      }
      expect(vm.isLockedOut, isTrue);

      vm..press('1')..press('2')..press('3')..press('4');
      expect(vm.submit(), isFalse,
          reason: 'lockout must survive a correct guess');
    });

    test('backspace and clear edit the entry', () async {
      final (_, vm) = await lockWithPin('1234');

      vm..press('1')..press('2')..press('3');
      vm.backspace();
      expect(vm.entryLength, 2);

      vm.clearEntry();
      expect(vm.entryLength, 0);

      vm.backspace();
      expect(vm.entryLength, 0, reason: 'backspace on empty is a no-op');
    });

    test('lock() re-locks an unlocked session', () async {
      final (_, vm) = await lockWithPin('1234');
      vm..press('1')..press('2')..press('3')..press('4');
      vm.submit();

      vm.lock();
      expect(vm.requiresUnlock, isTrue);
    });
  });

  group('PinLock', () {
    test('rejects weak PINs', () {
      expect(PinLock.validate('123'), contains('at least'));
      expect(PinLock.validate('1111'), contains('vary'));
      expect(PinLock.validate('12ab'), 'Digits only');
      expect(PinLock.validate('1234'), isNull);
    });

    test('stores a salted digest, never the PIN', () async {
      final storage = MemoryStorage();
      final lock = PinLock(storage);
      await lock.load();
      await lock.setPin('4821');

      final stored = await storage.read('ledger.pin.v1');
      expect(stored, isNotNull);
      expect(stored, isNot(contains('4821')));
      expect(stored, contains('hash'));
    });

    test('the same PIN gets a different digest each time it is set', () async {
      final a = PinLock(MemoryStorage());
      final b = PinLock(MemoryStorage());
      await a.load();
      await b.load();
      await a.setPin('4821');
      await b.setPin('4821');

      final storageA = MemoryStorage();
      final lockA = PinLock(storageA);
      await lockA.load();
      await lockA.setPin('4821');
      final digestA = await storageA.read('ledger.pin.v1');

      final storageB = MemoryStorage();
      final lockB = PinLock(storageB);
      await lockB.load();
      await lockB.setPin('4821');
      final digestB = await storageB.read('ledger.pin.v1');

      // Distinct salts, so identical PINs are not recognisable as identical.
      expect(digestA, isNot(digestB));
    });

    test('survives a reload', () async {
      final storage = MemoryStorage();
      final first = PinLock(storage);
      await first.load();
      await first.setPin('4821');

      final second = PinLock(storage);
      await second.load();

      expect(second.isConfigured, isTrue);
      expect(second.verify('0000'), isFalse);
      expect(second.verify('4821'), isTrue);
    });

    test('clearing removes the PIN', () async {
      final storage = MemoryStorage();
      final lock = PinLock(storage);
      await lock.load();
      await lock.setPin('4821');

      await lock.clear();

      expect(lock.isConfigured, isFalse);
      expect(await storage.read('ledger.pin.v1'), isNull);
    });
  });

  group('SettingsViewModel', () {
    Future<SettingsViewModel> build() async {
      final storage = MemoryStorage();
      final repo = await freshRepo(storage);
      final lock = PinLock(storage);
      await lock.load();
      return SettingsViewModel(lock, repo, LockViewModel(lock));
    }

    test('mismatched confirmation is rejected', () async {
      final vm = await build();
      expect(await vm.setPin('4821', '4822'), isFalse);
      expect(vm.pinError, contains('do not match'));
      expect(vm.hasPin, isFalse);
    });

    test('a weak PIN is rejected with the reason', () async {
      final vm = await build();
      expect(await vm.setPin('11', '11'), isFalse);
      expect(vm.pinError, contains('at least'));
    });

    test('a valid PIN is stored and can be removed', () async {
      final vm = await build();

      expect(await vm.setPin('4821', '4821'), isTrue);
      expect(vm.hasPin, isTrue);
      expect(vm.status, 'PIN updated');

      await vm.removePin();
      expect(vm.hasPin, isFalse);
    });
  });
}
