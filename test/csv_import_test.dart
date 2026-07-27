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
    test('strips currency and grouping separators', () {
      expect(tryParseCsvAmount('₹1,250.50'), 1250.50);
      expect(tryParseCsvAmount('\$3,000.00'), 3000);
      expect(tryParseCsvAmount('1234.56'), 1234.56);
      expect(tryParseCsvAmount('  42 '), 42);
    });

    test('keeps the sign so the caller can tell debits from credits', () {
      // Previously .abs()'d away, so a bank export that used the sign to
      // distinguish debits from credits lost direction entirely.
      expect(tryParseCsvAmount('-2000'), -2000);
      expect(tryParseCsvAmount('₹-1,250.50'), -1250.50);
      expect(tryParseCsvAmount('(1,234.56)'), -1234.56); // accounting style
    });

    test('reads European decimal notation', () {
      // "1.234,56" used to collapse to "1.234" and import as ₹1.23.
      expect(tryParseCsvAmount('1.234,56'), 1234.56);
      expect(tryParseCsvAmount('1.234.567,89'), 1234567.89);
      expect(tryParseCsvAmount('1,23'), 1.23);
      expect(tryParseCsvAmount('-1.234,56'), -1234.56);
    });

    test('treats a lone separator with three trailing digits as grouping', () {
      // Money doesn't carry three decimal places, so these are thousands.
      expect(tryParseCsvAmount('1,234'), 1234);
      expect(tryParseCsvAmount('1.234'), 1234);
      expect(tryParseCsvAmount('1.234.567'), 1234567);
    });

    test('rejects non-numeric', () {
      expect(tryParseCsvAmount('abc'), isNull);
      expect(tryParseCsvAmount(''), isNull);
      expect(tryParseCsvAmount('-'), isNull);
      expect(tryParseCsvAmount('.'), isNull);
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
      // Amounts are parsed into minor units (40000 * 100).
      expect(salary.amount, 4000000);
      expect(salary.date, DateTime(2026, 6, 1));

      final groceries = result.expenses[1];
      expect(groceries.type, DbConstants.txExpense);
      expect(groceries.amount, 120000); // ₹1,200.00

      // Empty category falls back to the default.
      expect(result.expenses[2].category, 'Other');
    });

    test('uses the amount sign as the type when no type column is mapped', () {
      // A bank export with signed amounts and no "kind" column: negative is a
      // debit, positive a credit. The stored amount stays positive either way.
      final result = parseCsvExpenses(
        [
          ['2026-06-01', 'Salary', '40000'],
          ['2026-06-02', 'Groceries', '-1.234,56'],
        ],
        hasHeader: false,
        mapping: const CsvColumnMapping(
            dateCol: 0, descriptionCol: 1, amountCol: 2),
      );

      expect(result.expenses[0].type, DbConstants.txIncome);
      expect(result.expenses[0].amount, 4000000);
      expect(result.expenses[1].type, DbConstants.txExpense);
      expect(result.expenses[1].amount, 123456); // ₹1,234.56, not ₹1.23
    });

    test('an all-positive export keeps the default type', () {
      // No negatives anywhere, so the sign says nothing and every row would
      // otherwise be flipped to income.
      final result = parseCsvExpenses(
        [
          ['2026-06-01', 'A', '10'],
          ['2026-06-02', 'B', '20'],
        ],
        hasHeader: false,
        mapping: const CsvColumnMapping(
            dateCol: 0, descriptionCol: 1, amountCol: 2),
      );

      expect(result.expenses.every((e) => e.type == DbConstants.txExpense),
          isTrue);
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
