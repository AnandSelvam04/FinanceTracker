import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/services/csv_import.dart';
import 'package:finance_tracker/utils/db_constants.dart';

/// Bank-statement CSVs: month-name dates, separate withdrawal/deposit
/// columns, an account to file the rows under, and rows the app already has
/// from SMS or hand entry.
void main() {
  group('month-name dates', () {
    test('day first', () {
      expect(tryParseCsvDate('01 Aug 2025'), DateTime(2025, 8, 1));
      expect(tryParseCsvDate('01-Aug-2025'), DateTime(2025, 8, 1));
      expect(tryParseCsvDate('1-aug-25'), DateTime(2025, 8, 1));
      expect(tryParseCsvDate('15 September 2025'), DateTime(2025, 9, 15));
      expect(tryParseCsvDate('15 Sept 2025'), DateTime(2025, 9, 15));
      expect(tryParseCsvDate('3 Mar, 2026'), DateTime(2026, 3, 3));
    });

    test('month first', () {
      expect(tryParseCsvDate('Aug 01, 2025'), DateTime(2025, 8, 1));
      expect(tryParseCsvDate('August 1 2025'), DateTime(2025, 8, 1));
      expect(tryParseCsvDate('Aug 1st, 2025'), DateTime(2025, 8, 1));
    });

    test('a trailing time of day is ignored', () {
      expect(tryParseCsvDate('01/08/2025 10:30:00'), DateTime(2025, 8, 1));
      expect(tryParseCsvDate('01-Aug-2025 10:30 AM'), DateTime(2025, 8, 1));
    });

    test('rejects what is not a date', () {
      expect(tryParseCsvDate('31 Feb 2026'), isNull);
      expect(tryParseCsvDate('01 Augment 2025'), isNull);
      expect(tryParseCsvDate('01 Foo 2025'), isNull);
    });
  });

  group('withdrawal and deposit columns', () {
    // An HDFC-style export.
    final rows = [
      ['Date', 'Narration', 'Ref', 'Withdrawal Amt.', 'Deposit Amt.', 'Bal'],
      ['01/08/25', 'UPI-SWIGGY', '1', '499.00', '', '10000.00'],
      ['02/08/25', 'NEFT SALARY', '2', '0.00', '50,000.00', '60000.00'],
      ['03/08/25', 'AMAZON REFUND', '3', '', '250.00', '60250.00'],
      ['04/08/25', 'BLANK ROW', '4', '', '', '60250.00'],
    ];
    const mapping = CsvColumnMapping(
        dateCol: 0, descriptionCol: 1, amountCol: 3, creditCol: 4);

    test('each row takes its direction from the filled column', () {
      final r = parseCsvExpenses(rows, hasHeader: true, mapping: mapping);
      expect(r.expenses, hasLength(3));
      expect(r.skipped, 1);

      final swiggy = r.expenses[0];
      expect(swiggy.type, DbConstants.txExpense);
      expect(swiggy.amount, 49900);

      final salary = r.expenses[1];
      expect(salary.type, DbConstants.txIncome);
      expect(salary.amount, 5000000);

      // A deposit that is a refund is still spending undone.
      final refund = r.expenses[2];
      expect(refund.isRefund, isTrue);
      expect(refund.amount, -25000);
    });

    test('the default type is not used when columns are split', () {
      const incomeDefault = CsvColumnMapping(
          dateCol: 0,
          descriptionCol: 1,
          amountCol: 3,
          creditCol: 4,
          defaultType: DbConstants.txIncome);
      final r = parseCsvExpenses(rows, hasHeader: true, mapping: incomeDefault);
      expect(r.expenses.first.type, DbConstants.txExpense);
    });
  });

  test('every row is filed against the chosen account', () {
    final r = parseCsvExpenses([
      ['01/08/2025', 'Lunch', '-120'],
      ['02/08/2025', 'Salary', '5000'],
    ],
        hasHeader: false,
        mapping: const CsvColumnMapping(
            dateCol: 0, descriptionCol: 1, amountCol: 2),
        accountId: 7);
    expect(r.expenses.map((e) => e.accountId), [7, 7]);
  });

  group('rows already recorded another way', () {
    Expense row(int amount, DateTime date,
            {String type = DbConstants.txExpense,
            int? accountId = 1,
            String description = 'x'}) =>
        Expense(
          description: description,
          amount: amount,
          date: date,
          category: 'Other',
          paymentMode: 'Other',
          type: type,
          accountId: accountId,
        );

    Expense recorded(int id, int amount, DateTime date,
            {String type = DbConstants.txExpense,
            int? accountId = 1,
            int? toAccountId,
            String? sourceRef = 'sms:vm-hdfcbk:1:abc'}) =>
        Expense(
          id: id,
          description: 'SWIGGY',
          amount: amount,
          date: date,
          category: 'Food',
          paymentMode: 'UPI',
          type: type,
          accountId: accountId,
          toAccountId: toAccountId,
          sourceRef: sourceRef,
        );

    final aug1 = DateTime(2025, 8, 1);

    test('an SMS-imported spend a day off is the same transaction', () {
      final result = CsvImportResult([row(49900, aug1)], 0)
          .withoutRecordedElsewhere(
              [recorded(1, 49900, aug1.add(const Duration(days: 1)))],
              accountId: 1);
      expect(result.expenses, isEmpty);
      expect(result.matchedExisting, 1);
    });

    test('a hand-entered row with no account matches too', () {
      final result = CsvImportResult([row(49900, aug1)], 0)
          .withoutRecordedElsewhere(
              [recorded(1, 49900, aug1, accountId: null, sourceRef: null)],
              accountId: 1);
      expect(result.expenses, isEmpty);
    });

    test('one recorded row absorbs only one statement row', () {
      final result = CsvImportResult([row(10000, aug1), row(10000, aug1)], 0)
          .withoutRecordedElsewhere([recorded(1, 10000, aug1)], accountId: 1);
      expect(result.expenses, hasLength(1));
      expect(result.matchedExisting, 1);
    });

    test('different amount, date, direction or account is not a match', () {
      final existing = [
        recorded(1, 50000, aug1), // amount
        recorded(2, 49900, aug1.add(const Duration(days: 5))), // too far
        recorded(3, 49900, aug1, type: DbConstants.txIncome), // direction
        recorded(4, 49900, aug1, accountId: 2), // another account
      ];
      final result = CsvImportResult([row(49900, aug1)], 0)
          .withoutRecordedElsewhere(existing, accountId: 1);
      expect(result.expenses, hasLength(1));
    });

    test('rows from an earlier CSV import are left to the exact check', () {
      final result = CsvImportResult([row(49900, aug1)], 0)
          .withoutRecordedElsewhere(
              [recorded(1, 49900, aug1, sourceRef: 'csv:2025-08-01|x')],
              accountId: 1);
      expect(result.expenses, hasLength(1));
    });

    test('a recorded transfer out of the account matches a withdrawal', () {
      final transfer = recorded(1, 2000000, aug1,
          type: DbConstants.txTransfer, accountId: 1, toAccountId: 2);
      final out = CsvImportResult([row(2000000, aug1)], 0)
          .withoutRecordedElsewhere([transfer], accountId: 1);
      expect(out.expenses, isEmpty);

      // …and the same transfer matches a deposit on the receiving account.
      final into = CsvImportResult(
              [row(2000000, aug1, type: DbConstants.txIncome, accountId: 2)], 0)
          .withoutRecordedElsewhere([transfer], accountId: 2);
      expect(into.expenses, isEmpty);

      // Without knowing the statement's account, a transfer can't be placed.
      final unknown = CsvImportResult([row(2000000, aug1, accountId: null)], 0)
          .withoutRecordedElsewhere([transfer]);
      expect(unknown.expenses, hasLength(1));
    });
  });

  group('guessStatementColumns', () {
    test('an HDFC header maps itself', () {
      final g = guessStatementColumns([
        'Date', 'Narration', 'Chq./Ref.No.', 'Value Dt', //
        'Withdrawal Amt.', 'Deposit Amt.', 'Closing Balance',
      ])!;
      expect(g.date, 0);
      expect(g.description, 1);
      expect(g.amount, 4);
      expect(g.credit, 5);
    });

    test('an SBI header with Debit/Credit', () {
      final g = guessStatementColumns([
        'Txn Date', 'Value Date', 'Description', 'Ref No./Cheque No.', //
        'Debit', 'Credit', 'Balance',
      ])!;
      expect(g.date, 0);
      expect(g.description, 2);
      expect(g.amount, 4);
      expect(g.credit, 5);
    });

    test('a single amount column stays single', () {
      final g = guessStatementColumns(['Date', 'Description', 'Amount'])!;
      expect(g.amount, 2);
      expect(g.credit, isNull);
    });

    test('a data row is not taken for a header', () {
      expect(guessStatementColumns(['01/08/2025', 'Lunch', '120']), isNull);
    });
  });
}
