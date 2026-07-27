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
    expect(formatMoney(100000), '\$1000.00');
  });

  group('formatMoneySigned', () {
    test('puts the minus sign before the currency symbol', () {
      // formatMoney would render this as the awkward '₹-7500.00'.
      expect(formatMoneySigned(-750000), '-₹7500.00');
      expect(formatMoney(-750000), '₹-7500.00');
    });

    test('leaves positive and zero amounts unsigned', () {
      expect(formatMoneySigned(750000), '₹7500.00');
      expect(formatMoneySigned(0), '₹0.00');
    });

    test('honors the configured currency symbol', () {
      CurrencyFormat.symbol = '\$';
      expect(formatMoneySigned(-100000), '-\$1000.00');
    });
  });
}
