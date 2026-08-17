import 'money.dart';

/// What a transaction does to an account balance.
enum TxKind {
  expense,
  income,
  transfer;

  static TxKind fromName(String name) =>
      TxKind.values.firstWhere((k) => k.name == name, orElse: () => expense);

  String get label => switch (this) {
        expense => 'Expense',
        income => 'Income',
        transfer => 'Transfer',
      };
}

enum AccountKind {
  cash,
  checking,
  savings,
  credit;

  static AccountKind fromName(String name) => AccountKind.values
      .firstWhere((k) => k.name == name, orElse: () => checking);

  String get label => switch (this) {
        cash => 'Cash',
        checking => 'Checking',
        savings => 'Savings',
        credit => 'Credit card',
      };

  /// Credit balances are owed, so a positive balance is a debt.
  bool get isLiability => this == credit;
}

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.kind,
    this.openingBalance = const Money.zero(),
    this.archived = false,
  });

  final String id;
  final String name;
  final AccountKind kind;
  final Money openingBalance;
  final bool archived;

  Account copyWith({
    String? name,
    AccountKind? kind,
    Money? openingBalance,
    bool? archived,
  }) =>
      Account(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        openingBalance: openingBalance ?? this.openingBalance,
        archived: archived ?? this.archived,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'openingBalance': openingBalance.cents,
        'archived': archived,
      };

  static Account fromJson(Map<String, Object?> json) => Account(
        id: json['id']! as String,
        name: json['name']! as String,
        kind: AccountKind.fromName(json['kind'] as String? ?? 'checking'),
        openingBalance: Money((json['openingBalance'] as int?) ?? 0),
        archived: (json['archived'] as bool?) ?? false,
      );
}

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.colorValue,
    this.monthlyBudget,
  });

  final String id;
  final String name;

  /// ARGB, stored as an int so the domain layer stays free of Flutter.
  final int colorValue;

  /// null means "no budget set" — distinct from a budget of zero.
  final Money? monthlyBudget;

  bool get hasBudget => monthlyBudget != null;

  Category copyWith({
    String? name,
    int? colorValue,
    Money? monthlyBudget,
    bool clearBudget = false,
  }) =>
      Category(
        id: id,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
        monthlyBudget: clearBudget ? null : (monthlyBudget ?? this.monthlyBudget),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'monthlyBudget': monthlyBudget?.cents,
      };

  static Category fromJson(Map<String, Object?> json) => Category(
        id: json['id']! as String,
        name: json['name']! as String,
        colorValue: (json['colorValue'] as int?) ?? 0xFF9E9E9E,
        monthlyBudget: json['monthlyBudget'] == null
            ? null
            : Money(json['monthlyBudget']! as int),
      );
}

class Transaction {
  const Transaction({
    required this.id,
    required this.accountId,
    required this.categoryId,
    required this.amount,
    required this.date,
    required this.kind,
    this.note = '',
  });

  final String id;
  final String accountId;

  /// Empty for transfers, which have no category.
  final String categoryId;

  /// Always stored positive; [kind] decides the direction.
  final Money amount;
  final DateTime date;
  final TxKind kind;
  final String note;

  /// The effect on the account balance.
  Money get signedAmount =>
      kind == TxKind.income ? amount : Money(-amount.cents);

  Transaction copyWith({
    String? accountId,
    String? categoryId,
    Money? amount,
    DateTime? date,
    TxKind? kind,
    String? note,
  }) =>
      Transaction(
        id: id,
        accountId: accountId ?? this.accountId,
        categoryId: categoryId ?? this.categoryId,
        amount: amount ?? this.amount,
        date: date ?? this.date,
        kind: kind ?? this.kind,
        note: note ?? this.note,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'accountId': accountId,
        'categoryId': categoryId,
        'amount': amount.cents,
        'date': date.toIso8601String(),
        'kind': kind.name,
        'note': note,
      };

  static Transaction fromJson(Map<String, Object?> json) => Transaction(
        id: json['id']! as String,
        accountId: json['accountId']! as String,
        categoryId: (json['categoryId'] as String?) ?? '',
        amount: Money((json['amount'] as int?) ?? 0),
        date: DateTime.parse(json['date']! as String),
        kind: TxKind.fromName(json['kind'] as String? ?? 'expense'),
        note: (json['note'] as String?) ?? '',
      );
}

/// A calendar month, used as the unit for budgets and rollups.
class Period implements Comparable<Period> {
  const Period(this.year, this.month);

  Period.of(DateTime date) : year = date.year, month = date.month;

  final int year;
  final int month;

  bool contains(DateTime date) => date.year == year && date.month == month;

  Period get previous =>
      month == 1 ? Period(year - 1, 12) : Period(year, month - 1);

  Period get next => month == 12 ? Period(year + 1, 1) : Period(year, month + 1);

  DateTime get start => DateTime(year, month);
  DateTime get end => DateTime(year, month + 1);

  static const _names = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String get label => '${_names[month - 1]} $year';
  String get shortLabel => '${_names[month - 1].substring(0, 3)} $year';

  @override
  int compareTo(Period other) =>
      year != other.year ? year.compareTo(other.year) : month.compareTo(other.month);

  @override
  bool operator ==(Object other) =>
      other is Period && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => label;
}
