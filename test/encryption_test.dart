import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;

  setUp(() async {
    DBService.dbNameOverride = 'encryption_test.db';
    await DBService().clearAll();
  });

  tearDown(() async {
    await DBService().clearAll();
  });

  test('encryption reports disabled in test mode', () async {
    expect(await DBService().isEncryptionEnabled(), isFalse);
  });

  test('table dump/restore preserves rows, ids, and account links', () async {
    final db = DBService();
    await db.insertAccount(
        Account(id: 1, name: 'Bank', type: 'bank', openingBalance: 5000));
    await db.insertExpense(Expense(
      description: 'linked',
      amount: 1000,
      date: DateTime(2026, 7, 1),
      category: 'Food',
      paymentMode: 'Cash',
      type: DbConstants.txExpense,
      accountId: 1,
    ));
    await db.insertExpense(Expense(
      description: 'unlinked',
      amount: 2000,
      date: DateTime(2026, 7, 2),
      category: 'Rent',
      paymentMode: 'Cash',
    ));

    // Exercises the same dump→restore copy the encryption migration uses.
    await db.debugRoundTripTables();

    final accounts = await db.getAccounts();
    final expenses = await db.getExpenses();
    expect(accounts.length, 1);
    expect(accounts.first.id, 1);
    expect(accounts.first.name, 'Bank');
    expect(expenses.length, 2);
    expect(expenses.where((e) => e.accountId == 1).length, 1);
    expect(expenses.map((e) => e.amount).toSet(), {1000, 2000});
  });
}
