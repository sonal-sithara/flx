/// Money, stored as an integer number of minor units (cents).
///
/// Doubles are never used for money — `0.1 + 0.2 != 0.3` is a rounding bug
/// waiting to show up in a balance.
class Money implements Comparable<Money> {
  const Money(this.cents);

  const Money.zero() : cents = 0;

  /// Parses user input: `12`, `12.5`, `1,234.56`, `-8.99`, `$4`.
  /// Returns null when the text is not a valid amount.
  static Money? tryParse(String input) {
    final cleaned = input.replaceAll(RegExp(r'[\s,$£€]'), '');
    if (cleaned.isEmpty) return null;

    final match = RegExp(r'^(-)?(\d*)(?:\.(\d{0,2}))?$').firstMatch(cleaned);
    if (match == null) return null;

    final whole = match.group(2) ?? '';
    final fraction = match.group(3) ?? '';
    if (whole.isEmpty && fraction.isEmpty) return null;

    // `12` -> 1200, `12.5` -> 1250, `.5` -> 50. padRight turns a one-digit
    // fraction into tenths rather than hundredths.
    final wholeCents = (int.tryParse(whole.isEmpty ? '0' : whole) ?? 0) * 100;
    final fractionCents = int.parse(fraction.padRight(2, '0'));

    final total = wholeCents + fractionCents;
    return Money(match.group(1) == '-' ? -total : total);
  }

  final int cents;

  bool get isZero => cents == 0;
  bool get isNegative => cents < 0;
  Money get abs => Money(cents.abs());

  Money operator +(Money other) => Money(cents + other.cents);
  Money operator -(Money other) => Money(cents - other.cents);
  Money operator -() => Money(-cents);

  bool operator >(Money other) => cents > other.cents;
  bool operator <(Money other) => cents < other.cents;
  bool operator >=(Money other) => cents >= other.cents;
  bool operator <=(Money other) => cents <= other.cents;

  /// Percentage of [total] this represents, clamped to 0..1.
  /// Returns 0 when [total] is zero rather than dividing by it.
  double fractionOf(Money total) {
    if (total.cents == 0) return 0;
    return (cents / total.cents).clamp(0.0, 1.0);
  }

  /// `1234.56` → `$1,234.56`; negatives render as `-$8.99`.
  String format({String symbol = r'$', bool showSign = false}) {
    final negative = cents < 0;
    final absolute = cents.abs();
    final whole = (absolute ~/ 100).toString();
    final fraction = (absolute % 100).toString().padLeft(2, '0');

    final grouped = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
      grouped.write(whole[i]);
    }

    final sign = negative
        ? '-'
        : showSign
            ? '+'
            : '';
    return '$sign$symbol$grouped.$fraction';
  }

  /// The form shown in a text field for editing: `1234.56`, no symbol.
  String toEditString() {
    final absolute = cents.abs();
    final sign = cents < 0 ? '-' : '';
    return '$sign${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
  }

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => format();
}
