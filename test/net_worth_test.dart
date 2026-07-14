import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/models/investment.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    DBService.dbNameOverride = 'net_worth_test.db';
    await DBService().clearAll();
  });

  tearDown(() async {
    await DBService().clearAll();
  });

  Expense e(int amount, DateTime date, {String type = DbConstants.txExpense}) =>
      Expense(
        description: 'x',
        amount: amount,
        date: date,
        category: 'General',
        paymentMode: 'Cash',
        type: type,
      );

  test('netWorthSeries tracks month-end value across accounts, flows, '
      'and investments', () async {
    final db = DBService();
    await db.insertAccount(Account(name: 'Bank', type: 'bank', openingBalance: 100000));
    await db.insertExpense(e(20000, DateTime(2026, 1, 10)));
    await db.insertExpense(
        e(50000, DateTime(2026, 2, 10), type: DbConstants.txIncome));
    await db.insertInvestment(Investment(
        name: 'Fund', amount: 30000, date: DateTime(2026, 3, 5), type: 'MF'));

    final series = await db.netWorthSeries(3, now: DateTime(2026, 3, 15));

    expect(series.length, 3);
    expect(series[0].value, 80000); // Jan end: 100000 - 20000
    expect(series[1].value, 130000); // Feb end: + 50000 income
    expect(series[2].value, 160000); // Mar end: + 30000 investment
    expect(series[0].month, DateTime(2026, 1, 1));
    expect(series[2].month, DateTime(2026, 3, 1));
  });

  test('netWorthSeries ignores transfers (they cancel across accounts)',
      () async {
    final db = DBService();
    await db.insertAccount(Account(name: 'A', type: 'bank', openingBalance: 50000));
    await db.insertAccount(Account(name: 'B', type: 'cash', openingBalance: 0));
    await db.insertExpense(Expense(
      description: 'move',
      amount: 10000,
      date: DateTime(2026, 2, 1),
      category: '',
      paymentMode: 'Other',
      type: DbConstants.txTransfer,
      accountId: 1,
      toAccountId: 2,
    ));

    final series = await db.netWorthSeries(2, now: DateTime(2026, 2, 10));
    expect(series.last.value, 50000); // unchanged by the transfer
  });

  test('getExpensesByDateRange returns only rows in the half-open interval',
      () async {
    final db = DBService();
    await db.insertExpense(e(100, DateTime(2026, 1, 31)));
    await db.insertExpense(e(200, DateTime(2026, 2, 15)));
    await db.insertExpense(e(300, DateTime(2026, 3, 1)));

    final rows = await db.getExpensesByDateRange(
        DateTime(2026, 2, 1), DateTime(2026, 3, 1));

    expect(rows.length, 1);
    expect(rows.first.amount, 200);
  });
}
