import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/services/receipt_parser.dart';

void main() {
  group('parseAmountToken', () {
    test('comma thousands, dot decimal', () {
      expect(ReceiptParser.parseAmountToken('1,234.50'), 123450);
    });
    test('european dot thousands, comma decimal', () {
      expect(ReceiptParser.parseAmountToken('1.234,50'), 123450);
    });
    test('plain integer becomes whole rupees', () {
      expect(ReceiptParser.parseAmountToken('499'), 49900);
    });
    test('simple decimal', () {
      expect(ReceiptParser.parseAmountToken('12.50'), 1250);
    });
    test('comma group of three is thousands, not decimal', () {
      expect(ReceiptParser.parseAmountToken('1,234'), 123400);
    });
    test('single decimal digit is padded', () {
      expect(ReceiptParser.parseAmountToken('3.5'), 350);
    });
    test('currency symbols are stripped', () {
      expect(ReceiptParser.parseAmountToken('₹ 2,150'), 215000);
    });
  });

  group('parse — amount', () {
    test('prefers the labelled grand total over subtotal/tax', () {
      final r = ReceiptParser.parse('''
DOMINOS PIZZA
Subtotal   559.00
GST         28.00
Total      587.00
''');
      expect(r.amountMinor, 58700);
    });

    test('a labelled total wins even when a larger figure is nearby', () {
      final r = ReceiptParser.parse('''
Store
Cash tendered 600.00
Total 587.00
Change 13.00
''');
      expect(r.amountMinor, 58700);
    });

    test('falls back to the largest ordinary figure with no total label', () {
      final r = ReceiptParser.parse('''
Cafe Coffee Day
Latte 180.00
Muffin 90.00
''');
      expect(r.amountMinor, 18000);
    });

    test('empty text yields no amount', () {
      expect(ReceiptParser.parse('').amountMinor, isNull);
    });
  });

  group('parse — date', () {
    test('ISO date', () {
      expect(ReceiptParser.parse('Date: 2025-08-12').date, DateTime(2025, 8, 12));
    });
    test('day-first numeric date', () {
      expect(
          ReceiptParser.parse('Billed 13/02/2025').date, DateTime(2025, 2, 13));
    });
    test('falls back to month-first when the first field cannot be a day', () {
      expect(
          ReceiptParser.parse('02/13/2025').date, DateTime(2025, 2, 13));
    });
    test('textual month', () {
      expect(ReceiptParser.parse('12 Aug 2025').date, DateTime(2025, 8, 12));
    });
    test('two-digit year expands to 2000s', () {
      expect(ReceiptParser.parse('12-Aug-25').date, DateTime(2025, 8, 12));
    });
  });

  group('parse — merchant', () {
    test('picks the first text line as the store name', () {
      final r = ReceiptParser.parse('''
STARBUCKS COFFEE
123 Main Street
Total 250.00
''');
      expect(r.merchant, 'STARBUCKS COFFEE');
    });

    test('skips a leading date line', () {
      final r = ReceiptParser.parse('''
2025-08-12
BIG BAZAAR
Total 999
''');
      expect(r.merchant, 'BIG BAZAAR');
    });
  });

  test('a receipt with nothing usable is empty', () {
    expect(ReceiptParser.parse('!!! ??? ...').isEmpty, isTrue);
  });
}
