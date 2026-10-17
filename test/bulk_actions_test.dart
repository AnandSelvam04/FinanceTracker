import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'bulk_actions_test.db';
  final db = DBService();

  setUp(() async => db.clearAll());
  tearDown(() async => db.clearAll());

  Future<int> add(String category, {String type = DbConstants.txExpense}) =>
      db.insertExpense(Expense(
        description: 'x',
        amount: 100,
        date: DateTime(2026, 5, 1),
        category: category,
        paymentMode: 'Cash',
        type: type,
        accountId: 1,
        toAccountId: type == DbConstants.txTransfer ? 2 : null,
      ));

  test('setCategory moves the chosen rows but never a transfer', () async {
    final a = await add('Other');
    final b = await add('Misc');
    final t = await add('Transfer', type: DbConstants.txTransfer);
    final untouched = await add('Other');

    expect(await db.setCategory([a, b, t], 'Groceries'), 2);
    final byId = {for (final e in await db.getExpensesByYear(2026)) e.id: e};
    expect(byId[a]!.category, 'Groceries');
    expect(byId[b]!.category, 'Groceries');
    expect(byId[t]!.category, 'Transfer');
    expect(byId[untouched]!.category, 'Other');
    expect(await db.setCategory([a], '  '), 0);
  });

  test('deleteExpenses removes exactly the chosen rows', () async {
    final a = await add('Food');
    final b = await add('Food');
    final keep = await add('Food');
    expect(await db.deleteExpenses([a, b]), 2);
    expect([for (final e in await db.getExpensesByYear(2026)) e.id], [keep]);
    expect(await db.deleteExpenses([]), 0);
  });

  test('bulk actions handle more rows than one statement can bind', () async {
    // Past SQLite's old 999-variable cap, so the IN list must be chunked.
    await db.insertExpenses([
      for (var i = 0; i < 1200; i++)
        Expense(
          description: 'x$i',
          amount: 100,
          date: DateTime(2026, 5, 1),
          category: 'Other',
          paymentMode: 'Cash',
        ),
    ]);
    final ids = [for (final e in await db.getExpensesByYear(2026)) e.id!];
    expect(ids.length, 1200);

    expect(await db.setCategory(ids, 'Food'), 1200);
    expect(await db.deleteExpenses(ids.take(1100)), 1100);
    final left = await db.getExpensesByYear(2026);
    expect(left.length, 100);
    expect(left.every((e) => e.category == 'Food'), isTrue);
  });
}
