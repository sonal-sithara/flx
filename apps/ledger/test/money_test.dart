import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/domain/models.dart';
import 'package:ledger/domain/money.dart';

void main() {
  group('Money.tryParse', () {
    test('parses whole amounts', () {
      expect(Money.tryParse('12')?.cents, 1200);
      expect(Money.tryParse('0')?.cents, 0);
      expect(Money.tryParse('1234')?.cents, 123400);
    });

    test('parses decimals, padding a single digit to tenths', () {
      expect(Money.tryParse('12.5')?.cents, 1250);
      expect(Money.tryParse('12.50')?.cents, 1250);
      expect(Money.tryParse('12.05')?.cents, 1205);
      expect(Money.tryParse('.5')?.cents, 50);
    });

    test('parses negatives', () {
      expect(Money.tryParse('-8.99')?.cents, -899);
      expect(Money.tryParse('-0.01')?.cents, -1);
    });

    test('strips currency symbols, spaces and thousands separators', () {
      expect(Money.tryParse(r'$1,234.56')?.cents, 123456);
      expect(Money.tryParse('  42 ')?.cents, 4200);
      expect(Money.tryParse('£9.99')?.cents, 999);
    });

    test('rejects anything that is not an amount', () {
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse('1.2.3'), isNull);
      expect(Money.tryParse('12-'), isNull);
      expect(Money.tryParse('.'), isNull);
    });

    test('rejects more than two decimal places rather than rounding', () {
      // Silently dropping a digit would make 12.567 become 12.56 with no
      // indication the input was wrong.
      expect(Money.tryParse('12.567'), isNull);
    });
  });

  group('Money.format', () {
    test('groups thousands and always shows two decimals', () {
      expect(const Money(123456).format(), r'$1,234.56');
      expect(const Money(100).format(), r'$1.00');
      expect(const Money(0).format(), r'$0.00');
      expect(const Money(5).format(), r'$0.05');
    });

    test('groups larger numbers correctly', () {
      expect(const Money(123456789).format(), r'$1,234,567.89');
      expect(const Money(100000).format(), r'$1,000.00');
    });

    test('renders negatives with the sign before the symbol', () {
      expect(const Money(-899).format(), r'-$8.99');
    });

    test('showSign adds a plus for positives only', () {
      expect(const Money(500).format(showSign: true), r'+$5.00');
      expect(const Money(-500).format(showSign: true), r'-$5.00');
      expect(const Money(0).format(showSign: true), r'+$0.00');
    });

    test('toEditString round-trips through tryParse', () {
      for (final cents in [0, 5, 100, 1250, 123456, -899]) {
        final money = Money(cents);
        expect(Money.tryParse(money.toEditString())?.cents, cents,
            reason: 'failed to round-trip $cents');
      }
    });
  });

  group('Money arithmetic', () {
    test('adds and subtracts exactly', () {
      // The reason money is an int: 0.1 + 0.2 != 0.3 in binary floating point.
      expect((const Money(10) + const Money(20)).cents, 30);
      expect((const Money(1000) - const Money(1)).cents, 999);
      expect((-const Money(500)).cents, -500);
    });

    test('compares', () {
      expect(const Money(100) > const Money(99), isTrue);
      expect(const Money(100) >= const Money(100), isTrue);
      expect(const Money(-1) < const Money(0), isTrue);
    });

    test('equality is by value', () {
      expect(const Money(100), const Money(100));
      // The duplicate is deliberate: it proves hashCode agrees with ==.
      // ignore: equal_elements_in_set
      expect({const Money(100), const Money(100)}.length, 1);
    });

    test('fractionOf clamps and never divides by zero', () {
      expect(const Money(50).fractionOf(const Money(100)), 0.5);
      expect(const Money(200).fractionOf(const Money(100)), 1.0);
      expect(const Money(50).fractionOf(const Money.zero()), 0.0);
    });
  });

  group('Period', () {
    test('rolls over year boundaries', () {
      expect(const Period(2026, 12).next, const Period(2027, 1));
      expect(const Period(2026, 1).previous, const Period(2025, 12));
    });

    test('contains only its own month', () {
      const march = Period(2026, 3);
      expect(march.contains(DateTime(2026, 3, 1)), isTrue);
      expect(march.contains(DateTime(2026, 3, 31, 23, 59)), isTrue);
      expect(march.contains(DateTime(2026, 4, 1)), isFalse);
      expect(march.contains(DateTime(2025, 3, 15)), isFalse);
    });

    test('labels and sorts', () {
      expect(const Period(2026, 3).label, 'March 2026');
      expect(const Period(2026, 3).shortLabel, 'Mar 2026');
      expect(const Period(2026, 1).compareTo(const Period(2026, 2)), lessThan(0));
      expect(const Period(2027, 1).compareTo(const Period(2026, 12)),
          greaterThan(0));
    });
  });

  group('Transaction', () {
    test('income adds and expense subtracts from a balance', () {
      final income = Transaction(
        id: 'a',
        accountId: 'x',
        categoryId: 'c',
        amount: const Money(1000),
        date: DateTime(2026),
        kind: TxKind.income,
      );
      expect(income.signedAmount.cents, 1000);
      expect(income.copyWith(kind: TxKind.expense).signedAmount.cents, -1000);
    });

    test('survives a JSON round trip', () {
      final original = Transaction(
        id: 'tx-1',
        accountId: 'acc-1',
        categoryId: 'cat-1',
        amount: const Money(4295),
        date: DateTime(2026, 3, 14, 9, 30),
        kind: TxKind.expense,
        note: 'Coffee',
      );
      final restored = Transaction.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.amount, original.amount);
      expect(restored.date, original.date);
      expect(restored.kind, original.kind);
      expect(restored.note, original.note);
    });
  });
}
