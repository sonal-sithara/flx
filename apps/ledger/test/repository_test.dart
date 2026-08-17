import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/data/ledger_repository.dart';
import 'package:ledger/data/storage.dart';
import 'package:ledger/domain/models.dart';
import 'package:ledger/domain/money.dart';

Future<LedgerRepository> freshRepo([MemoryStorage? storage]) async {
  final repo = LedgerRepository(storage ?? MemoryStorage());
  await repo.load();
  return repo;
}

void main() {
  group('load', () {
    test('seeds a realistic ledger on first launch', () async {
      final repo = await freshRepo();

      expect(repo.isLoaded, isTrue);
      expect(repo.accounts, isNotEmpty);
      expect(repo.categories, isNotEmpty);
      expect(repo.query(const TxQuery()).total, greaterThan(50));
    });

    test('restores what was persisted instead of reseeding', () async {
      final storage = MemoryStorage();
      final first = await freshRepo(storage);
      await first.upsertTransaction(
        accountId: first.accounts.first.id,
        categoryId: first.categories.first.id,
        amount: const Money(1234),
        date: DateTime.now(),
        kind: TxKind.expense,
        note: 'Marker',
      );
      final countAfterWrite = first.query(const TxQuery()).total;

      final second = await freshRepo(storage);
      expect(second.query(const TxQuery()).total, countAfterWrite);
      expect(
        second.query(const TxQuery(search: 'Marker')).total,
        1,
        reason: 'the written transaction should survive a reload',
      );
    });

    test('treats corrupt storage as empty rather than crashing', () async {
      final storage = MemoryStorage({'ledger.v1': 'not json at all'});
      final repo = await freshRepo(storage);

      // A user who cannot open the app cannot recover their data either.
      expect(repo.isLoaded, isTrue);
      expect(repo.accounts, isNotEmpty);
    });
  });

  group('balances', () {
    test('balance is opening plus signed transactions', () async {
      final repo = await freshRepo(MemoryStorage());
      final account = await repo.upsertAccount(
        name: 'Test',
        kind: AccountKind.checking,
        openingBalance: const Money(10000),
      );

      await repo.upsertTransaction(
        accountId: account.id,
        categoryId: repo.categories.first.id,
        amount: const Money(2500),
        date: DateTime.now(),
        kind: TxKind.expense,
      );
      await repo.upsertTransaction(
        accountId: account.id,
        categoryId: repo.categories.first.id,
        amount: const Money(500),
        date: DateTime.now(),
        kind: TxKind.income,
      );

      expect(repo.balanceOf(account.id).cents, 10000 - 2500 + 500);
    });

    test('an unknown account has a zero balance', () async {
      final repo = await freshRepo();
      expect(repo.balanceOf('nope'), const Money.zero());
    });

    test('credit balances subtract from net worth', () async {
      final storage = MemoryStorage();
      final repo = LedgerRepository(storage);
      await repo.load();
      await repo.reset();

      final before = repo.netWorth;
      final card = await repo.upsertAccount(
        name: 'Card',
        kind: AccountKind.credit,
        openingBalance: const Money(-5000),
      );

      // A credit account holding -5000 is 5000 owed, so net worth rises by
      // 5000 when the liability is negated.
      expect(repo.netWorth.cents, before.cents + 5000);
      expect(repo.account(card.id)!.kind.isLiability, isTrue);
    });
  });

  group('query', () {
    test('paginates without repeating or dropping rows', () async {
      final repo = await freshRepo();
      final total = repo.query(const TxQuery()).total;

      final seen = <String>[];
      var offset = 0;
      while (offset < total) {
        final page = repo.query(const TxQuery(), offset: offset, limit: 10);
        seen.addAll(page.items.map((t) => t.id));
        offset = page.nextOffset;
        if (page.items.isEmpty) break;
      }

      expect(seen.length, total);
      expect(seen.toSet().length, total, reason: 'a row appeared twice');
    });

    test('returns newest first', () async {
      final repo = await freshRepo();
      final items = repo.query(const TxQuery(), limit: 30).items;

      for (var i = 1; i < items.length; i++) {
        expect(
          items[i - 1].date.isBefore(items[i].date),
          isFalse,
          reason: 'ordering broke at index $i',
        );
      }
    });

    test('search matches notes and category names', () async {
      final repo = await freshRepo(MemoryStorage());
      final account = repo.accounts.first;
      final category = repo.categories
          .firstWhere((c) => c.name == 'Groceries', orElse: () => repo.categories.first);

      await repo.upsertTransaction(
        accountId: account.id,
        categoryId: category.id,
        amount: const Money(999),
        date: DateTime.now(),
        kind: TxKind.expense,
        note: 'Zebra crossing fee',
      );

      expect(repo.query(const TxQuery(search: 'zebra')).total, 1,
          reason: 'search should be case-insensitive');
      expect(repo.query(const TxQuery(search: 'ZEBRA')).total, 1);
      expect(repo.query(const TxQuery(search: 'nothing here')).total, 0);
    });

    test('filters combine with AND', () async {
      final repo = await freshRepo();
      final account = repo.accounts.first;

      final byAccount = repo.query(TxQuery(accountId: account.id)).total;
      final byAccountAndIncome = repo
          .query(TxQuery(accountId: account.id, kind: TxKind.income))
          .total;

      expect(byAccountAndIncome, lessThanOrEqualTo(byAccount));
      for (final tx
          in repo.query(TxQuery(accountId: account.id, kind: TxKind.income), limit: 100).items) {
        expect(tx.accountId, account.id);
        expect(tx.kind, TxKind.income);
      }
    });

    test('period filter keeps only that month', () async {
      final repo = await freshRepo();
      final period = Period.of(DateTime.now());

      for (final tx in repo.query(TxQuery(period: period), limit: 200).items) {
        expect(period.contains(tx.date), isTrue);
      }
    });

    test('an offset past the end returns an empty page, not an error', () async {
      final repo = await freshRepo();
      final page = repo.query(const TxQuery(), offset: 100000, limit: 10);

      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });

  group('budgets', () {
    test('budget lines sum only that month\'s expenses', () async {
      final repo = await freshRepo(MemoryStorage());
      await repo.reset();

      final category = repo.categories.first;
      await repo.setBudget(category.id, const Money(10000));

      final period = Period.of(DateTime.now());
      final before = repo
          .budgetLines(period)
          .firstWhere((l) => l.category.id == category.id)
          .spent;

      await repo.upsertTransaction(
        accountId: repo.accounts.first.id,
        categoryId: category.id,
        amount: const Money(2500),
        date: DateTime.now(),
        kind: TxKind.expense,
      );
      // Income must not count toward spend.
      await repo.upsertTransaction(
        accountId: repo.accounts.first.id,
        categoryId: category.id,
        amount: const Money(9999),
        date: DateTime.now(),
        kind: TxKind.income,
      );

      final after = repo
          .budgetLines(period)
          .firstWhere((l) => l.category.id == category.id)
          .spent;

      expect(after.cents - before.cents, 2500);
    });

    test('isOver and fraction behave at the boundary', () async {
      final repo = await freshRepo();
      const category = Category(id: 'c', name: 'C', colorValue: 0);

      const exactly = BudgetLine(
        category: category,
        spent: Money(10000),
        budget: Money(10000),
      );
      const over = BudgetLine(
        category: category,
        spent: Money(10001),
        budget: Money(10000),
      );

      expect(exactly.isOver, isFalse, reason: 'spending it all is not over');
      expect(exactly.fraction, 1.0);
      expect(over.isOver, isTrue);
      expect(over.fraction, 1.0, reason: 'the bar clamps');
      expect(over.remaining.cents, -1);
      expect(repo.isLoaded, isTrue);
    });

    test('a category with no budget reports none', () async {
      const line = BudgetLine(
        category: Category(id: 'c', name: 'C', colorValue: 0),
        spent: Money(500),
        budget: null,
      );
      expect(line.hasBudget, isFalse);
      expect(line.isOver, isFalse);
      expect(line.fraction, 0);
    });
  });

  group('writes', () {
    test('archiving hides an account without orphaning transactions', () async {
      final repo = await freshRepo();
      final account = repo.accounts.first;
      final txCount = repo.query(TxQuery(accountId: account.id)).total;

      await repo.archiveAccount(account.id);

      expect(repo.accounts.any((a) => a.id == account.id), isFalse);
      expect(repo.allAccounts.any((a) => a.id == account.id), isTrue);
      expect(repo.query(TxQuery(accountId: account.id)).total, txCount);
    });

    test('amounts are stored positive regardless of sign entered', () async {
      final repo = await freshRepo();
      final tx = await repo.upsertTransaction(
        accountId: repo.accounts.first.id,
        categoryId: repo.categories.first.id,
        amount: const Money(-2500),
        date: DateTime.now(),
        kind: TxKind.expense,
      );

      expect(tx.amount.cents, 2500);
      expect(tx.signedAmount.cents, -2500);
    });

    test('generated ids are unique even within the same millisecond', () async {
      final repo = await freshRepo();
      final ids = <String>{};
      for (var i = 0; i < 50; i++) {
        final tx = await repo.upsertTransaction(
          accountId: repo.accounts.first.id,
          categoryId: repo.categories.first.id,
          amount: const Money(1),
          date: DateTime.now(),
          kind: TxKind.expense,
        );
        ids.add(tx.id);
      }
      expect(ids.length, 50);
    });

    test('notifies listeners on every write', () async {
      final repo = await freshRepo();
      var notifications = 0;
      repo.addListener(() => notifications++);

      await repo.upsertTransaction(
        accountId: repo.accounts.first.id,
        categoryId: repo.categories.first.id,
        amount: const Money(100),
        date: DateTime.now(),
        kind: TxKind.expense,
      );
      expect(notifications, 1);

      await repo.setBudget(repo.categories.first.id, const Money(500));
      expect(notifications, 2);

      await repo.deleteTransaction(repo.query(const TxQuery()).items.first.id);
      expect(notifications, 3);
    });

    test('reset restores the starter ledger', () async {
      final repo = await freshRepo();
      final tx = await repo.upsertTransaction(
        accountId: repo.accounts.first.id,
        categoryId: repo.categories.first.id,
        amount: const Money(100),
        date: DateTime.now(),
        kind: TxKind.expense,
        note: 'Doomed',
      );

      await repo.reset();

      expect(repo.transaction(tx.id), isNull);
      expect(repo.query(const TxQuery(search: 'Doomed')).total, 0);
      expect(repo.accounts, isNotEmpty);
    });
  });
}
