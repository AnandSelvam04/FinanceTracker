import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/services/csv_import.dart';
import 'package:finance_tracker/utils/db_constants.dart';

void main() {
  group('tryParseCsvDate', () {
    test('parses ISO dates', () {
      expect(tryParseCsvDate('2026-06-15'), DateTime(2026, 6, 15));
    });
    test('parses day-first dd/MM/yyyy', () {
      expect(tryParseCsvDate('15/06/2026'), DateTime(2026, 6, 15));
      expect(tryParseCsvDate('01-02-24'), DateTime(2024, 2, 1));
    });
    test('rejects invalid dates', () {
      expect(tryParseCsvDate('31/02/2026'), isNull);
      expect(tryParseCsvDate('not a date'), isNull);
      expect(tryParseCsvDate(''), isNull);
    });
  });

  group('tryParseCsvAmount', () {
    test('strips currency, commas, and sign', () {
      expect(tryParseCsvAmount('₹1,250.50'), 1250.50);
      expect(tryParseCsvAmount('-2000'), 2000);
      expect(tryParseCsvAmount('\$3,000.00'), 3000);
    });
    test('rejects non-numeric', () {
      expect(tryParseCsvAmount('abc'), isNull);
      expect(tryParseCsvAmount(''), isNull);
    });
  });

  group('parseCsvExpenses', () {
    final rows = <List<dynamic>>[
      ['Date', 'Note', 'Amount', 'Category', 'Kind'],
      ['2026-06-01', 'Salary', '40000', 'Salary', 'credit'],
      ['02/06/2026', 'Groceries', '₹1,200', 'Food', 'debit'],
      ['bad-date', 'Broken', '100', 'X', 'debit'],
      ['2026-06-03', 'No category', '50', '', 'debit'],
    ];

    const mapping = CsvColumnMapping(
      dateCol: 0,
      descriptionCol: 1,
      amountCol: 2,
      categoryCol: 3,
      typeCol: 4,
    );

    test('maps columns, skips bad rows, honors header', () {
      final result =
          parseCsvExpenses(rows, hasHeader: true, mapping: mapping);
      expect(result.expenses.length, 3);
      expect(result.skipped, 1); // the bad-date row

      final salary = result.expenses[0];
      expect(salary.type, DbConstants.txIncome);
      expect(salary.amount, 40000);
      expect(salary.date, DateTime(2026, 6, 1));

      final groceries = result.expenses[1];
      expect(groceries.type, DbConstants.txExpense);
      expect(groceries.amount, 1200);

      // Empty category falls back to the default.
      expect(result.expenses[2].category, 'Other');
    });

    test('without header includes the first row', () {
      final result = parseCsvExpenses(
        [
          ['2026-06-01', 'A', '10', 'Food', 'debit'],
        ],
        hasHeader: false,
        mapping: mapping,
      );
      expect(result.expenses.length, 1);
    });
  });
}
