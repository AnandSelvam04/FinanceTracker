import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/transaction_filter.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'transaction_note_test.db';

  Expense tx({String? note}) => Expense(
        description: 'Croma',
        amount: 4999900,
        date: DateTime(2026, 9, 10),
        category: 'Shopping',
        paymentMode: 'Credit Card',
        note: note,
      );

  test('a note is saved and read back', () async {
    await DBService().clearAll();
    await DBService().insertExpense(tx(note: 'Warranty till 2028'));
    final rows = await DBService().getExpensesByYear(2026);
    expect(rows.single.note, 'Warranty till 2028');
    await DBService().clearAll();
  });

  test('blank notes count as none, and old rows have none', () {
    expect(tx(note: '   ').noteText, isNull);
    expect(tx().noteText, isNull);
    expect(
        Expense.fromMap({
          'description': 'x',
          'amount': 1,
          'date': '2020-01-01T00:00:00.000',
          'category': 'Food',
          'paymentMode': 'Cash',
        }).note,
        isNull);
  });

  test('search finds a transaction by its note', () {
    final filter = TransactionFilter(searchQuery: 'warranty', year: 2026);
    expect(filter.matches(tx(note: 'Warranty till 2028')), isTrue);
    expect(filter.matches(tx()), isFalse);
  });
}
