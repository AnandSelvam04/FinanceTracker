import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/models/investment.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/providers/settings_provider.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/services/notification_service.dart';
import 'package:finance_tracker/utils/account_ledger.dart';
import 'package:finance_tracker/utils/db_constants.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'account_statement_test.db';

  Expense tx(int amount, DateTime date,
          {String type = DbConstants.txExpense,
          int? accountId = 1,
          int? toAccountId,
          int? toAmount}) =>
      Expense(
        description: 'x',
        amount: amount,
        date: date,
        category: type == DbConstants.txTransfer ? 'Transfer' : 'Food',
        paymentMode: 'Cash',
        type: type,
        accountId: accountId,
        toAccountId: toAccountId,
        toAmount: toAmount,
      );

  group('accountLedger', () {
    test('runs from the opening balance, newest first', () {
      final ledger = accountLedger(
        accountId: 1,
        openingBalance: 10000,
        transactions: [
          tx(2000, DateTime(2026, 1, 3)), // spend
          tx(50000, DateTime(2026, 1, 1), type: DbConstants.txIncome),
          tx(-500, DateTime(2026, 1, 4)), // refund
          // Out to account 2, and in from account 3 (received in our currency).
          tx(3000, DateTime(2026, 1, 5),
              type: DbConstants.txTransfer, toAccountId: 2),
          tx(100, DateTime(2026, 1, 6),
              type: DbConstants.txTransfer,
              accountId: 3,
              toAccountId: 1,
              toAmount: 8300),
          // Not this account's at all.
          tx(999, DateTime(2026, 1, 2), accountId: 2),
        ],
        investments: [
          Investment(
              name: 'Nifty',
              amount: 4000,
              date: DateTime(2026, 1, 7),
              type: 'Mutual Funds',
              accountId: 1),
          Investment(
              name: 'Other acct',
              amount: 1,
              date: DateTime(2026, 1, 7),
              type: 'Stocks',
              accountId: 2),
        ],
      );
      expect([for (final e in ledger) e.delta],
          [-4000, 8300, -3000, 500, -2000, 50000]);
      expect([for (final e in ledger) e.balanceAfter],
          [59800, 63800, 55500, 58500, 58000, 60000]);
    });

    test('matches the balance the Accounts screen computes', () async {
      await DBService().clearAll();
      final a = await DBService()
          .insertAccount(Account(name: 'A', type: 'bank', openingBalance: 700));
      final b =
          await DBService().insertAccount(Account(name: 'B', type: 'bank'));
      await DBService()
          .insertExpense(tx(300, DateTime(2024, 3, 1), accountId: a));
      await DBService().insertExpense(tx(1000, DateTime(2026, 3, 1),
          type: DbConstants.txIncome, accountId: a));
      await DBService().insertExpense(tx(200, DateTime(2026, 4, 1),
          type: DbConstants.txTransfer, accountId: b, toAccountId: a));
      await DBService()
          .insertExpense(tx(50, DateTime(2026, 4, 2), accountId: b));

      final rows = await DBService().getExpensesForAccount(a);
      expect(rows, hasLength(3)); // every year, both directions, not B's spend
      final ledger =
          accountLedger(accountId: a, openingBalance: 700, transactions: rows);
      final flows = await DBService().getAccountFlows();
      expect(ledger.first.balanceAfter, 700 + flows[a]!);
      await DBService().clearAll();
    });
  });

  test('deleting a row from a year that is not loaded still deletes it',
      () async {
    await DBService().clearAll();
    final id = await DBService().insertExpense(tx(100, DateTime(2019, 5, 1)));
    final provider = ExpenseProvider();
    var notified = 0;
    provider.addListener(() => notified++);
    await provider.deleteExpense(id);
    expect(await DBService().getExpensesForAccount(1), isEmpty);
    expect(notified, greaterThan(0));
    await DBService().clearAll();
  });

  group('daily reminder', () {
    final evening = 21 * 60;
    test('fires today when the time is ahead and nothing is logged', () {
      expect(
          NotificationService.nextDailyReminder(
              DateTime(2026, 10, 3, 18), evening,
              loggedToday: false),
          DateTime(2026, 10, 3, 21));
    });

    test('skips to tomorrow once something is logged, or the time passed', () {
      expect(
          NotificationService.nextDailyReminder(
              DateTime(2026, 10, 3, 18), evening,
              loggedToday: true),
          DateTime(2026, 10, 4, 21));
      expect(
          NotificationService.nextDailyReminder(
              DateTime(2026, 10, 31, 22), evening,
              loggedToday: false),
          DateTime(2026, 11, 1, 21));
    });

    test('the setting persists and can be turned off', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsProvider();
      await s.load();
      expect(s.dailyReminderMinutes, isNull);
      await s.setDailyReminderMinutes(20 * 60 + 30);
      final reloaded = SettingsProvider();
      await reloaded.load();
      expect(reloaded.dailyReminderMinutes, 20 * 60 + 30);
      await reloaded.setDailyReminderMinutes(null);
      await s.load();
      expect(s.dailyReminderMinutes, isNull);
    });
  });
}
