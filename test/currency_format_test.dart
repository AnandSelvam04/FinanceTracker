import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/utils/currency_format.dart';

void main() {
  tearDown(() => CurrencyFormat.symbol = '₹');

  test('rupeesToMinor rounds to whole minor units', () {
    expect(rupeesToMinor(120.50), 12050);
    expect(rupeesToMinor(0.1), 10);
    // The classic float case rounds cleanly instead of drifting.
    expect(rupeesToMinor(0.1 + 0.2), 30);
  });

  test('parseMinor parses user strings to minor units', () {
    expect(parseMinor('1234.56'), 123456);
    expect(parseMinor('  50 '), 5000);
    expect(parseMinor('abc'), isNull);
  });

  test('minorToEditString and formatMoney round-trip', () {
    expect(minorToEditString(12050), '120.50');
    expect(formatMoney(12050), '₹120.50');
    expect(formatMoneyRounded(12050), '₹121');
  });

  test('formatMoney honors the configured currency symbol', () {
    CurrencyFormat.symbol = '\$';
    expect(formatMoney(100000), '\$1,000.00');
  });

  group('digit grouping', () {
    test('rupee amounts use lakh/crore grouping', () {
      expect(formatMoney(99900), '₹999.00');
      expect(formatMoney(100000), '₹1,000.00');
      expect(formatMoney(67530000), '₹6,75,300.00');
      expect(formatMoney(1234567890), '₹1,23,45,678.90');
      expect(formatMoneyRounded(1234567890), '₹1,23,45,679');
    });

    test('other symbols use thousands grouping', () {
      CurrencyFormat.symbol = '\$';
      expect(formatMoney(123456789), '\$1,234,567.89');
      expect(formatMoneyIn('€', 100000000), '€1,000,000.00');
      // An explicit rupee symbol still groups the Indian way.
      expect(formatMoneyIn('₹', 10000000), '₹1,00,000.00');
    });

    test('negative amounts keep their sign ahead of the digits', () {
      expect(formatMoneySigned(-123456700), '-₹12,34,567.00');
      expect(formatMoneyRounded(-150000), '₹-1,500');
    });
  });

  group('formatMoneySigned', () {
    test('puts the minus sign before the currency symbol', () {
      // formatMoney would render this as the awkward '₹-7,500.00'.
      expect(formatMoneySigned(-750000), '-₹7,500.00');
      expect(formatMoney(-750000), '₹-7,500.00');
    });

    test('leaves positive and zero amounts unsigned', () {
      expect(formatMoneySigned(750000), '₹7,500.00');
      expect(formatMoneySigned(0), '₹0.00');
    });

    test('honors the configured currency symbol', () {
      CurrencyFormat.symbol = '\$';
      expect(formatMoneySigned(-100000), '-\$1,000.00');
    });
  });

  group('formatMoneySignedIn', () {
    test('puts the minus before the symbol', () {
      // A credit card balance is what is owed, so this is the common case on
      // the Accounts screen rather than an edge case.
      expect(formatMoneySignedIn('\u20b9', -2215000), '-\u20b922,150.00');
    });

    test('leaves a positive balance unsigned', () {
      expect(formatMoneySignedIn('\u20b9', 2215000), '\u20b922,150.00');
    });

    test('zero has no sign', () {
      expect(formatMoneySignedIn('\u20b9', 0), '\u20b90.00');
    });

    test('honours a foreign account symbol', () {
      expect(formatMoneySignedIn('\u0024', -50025), '-\u0024500.25');
    });

    test('agrees with formatMoneyIn when positive', () {
      expect(formatMoneySignedIn('\u20b9', 1234),
          formatMoneyIn('\u20b9', 1234));
    });
  });
}
