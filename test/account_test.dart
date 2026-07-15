import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/models/recurring_rule.dart';
import 'package:finance_tracker/models/tx_template.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;

  setUp(() async {
    DBService.dbNameOverride = 'account_test.db';
    await DBService().clearAll();
  });

  tearDown(() async {
    await DBService().clearAll();
  });

  Expense tx({
    required int amount,
    required String type,
    int? accountId,
    int? toAccountId,
    DateTime? date,
    String category = 'Other',
  }) =>
      Expense(
        description: 'test',
        amount: amount,
        date: date ?? DateTime(2026, 6, 15),
        category: category,
        paymentMode: 'Cash',
        type: type,
        accountId: accountId,
        toAccountId: toAccountId,
      );

  group('Account balance', () {
    test('opening + income − expenses ± transfers', () async {
      final db = DBService();
      final cashId = await db.insertAccount(
          Account(name: 'Cash', type: 'cash', openingBalance: 1000));
      final bankId = await db.insertAccount(
          Account(name: 'Bank', type: 'bank', openingBalance: 5000));

      await db.insertExpense(tx(
          amount: 200, type: DbConstants.txExpense, accountId: cashId));
      await db.insertExpense(
          tx(amount: 3000, type: DbConstants.txIncome, accountId: bankId));
      // Transfer 500 bank → cash
      await db.insertExpense(tx(
          amount: 500,
          type: DbConstants.txTransfer,
          accountId: bankId,
          toAccountId: cashId));

      final accounts = await db.getAccounts();
      final cash = accounts.firstWhere((a) => a.id == cashId);
      final bank = accounts.firstWhere((a) => a.id == bankId);

      expect(await db.getAccountBalance(cash), 1000 - 200 + 500); // 1300
      expect(await db.getAccountBalance(bank), 5000 + 3000 - 500); // 7500
    });

    test('deleting an account detaches it from transactions', () async {
      final db = DBService();
      final cashId =
          await db.insertAccount(Account(name: 'Cash', type: 'cash'));
      final bankId =
          await db.insertAccount(Account(name: 'Bank', type: 'bank'));
      await db.insertExpense(tx(
          amount: 100, type: DbConstants.txExpense, accountId: cashId));
      await db.insertExpense(tx(
          amount: 200,
          type: DbConstants.txTransfer,
          accountId: bankId,
          toAccountId: cashId));

      await db.deleteAccount(cashId);

      final expenses = await db.getExpenses();
      expect(expenses.any((e) => e.accountId == cashId), isFalse);
      expect(expenses.any((e) => e.toAccountId == cashId), isFalse);
      // The other account's link is untouched.
      expect(expenses.any((e) => e.accountId == bankId), isTrue);
    });

    test('deleting an account detaches recurring rules and templates',
        () async {
      final db = DBService();
      final cashId =
          await db.insertAccount(Account(name: 'Cash', type: 'cash'));
      await db.insertRecurringRule(RecurringRule(
        description: 'Rent',
        amount: 1000,
        category: 'Housing',
        type: DbConstants.txExpense,
        accountId: cashId,
        frequency: DbConstants.freqMonthly,
        nextDue: DateTime(2026, 7, 1),
        anchorDay: 1,
      ));
      await db.insertTemplate(TxTemplate(
        name: 'Chai',
        description: 'Chai',
        amount: 20,
        category: 'Food',
        type: DbConstants.txExpense,
        accountId: cashId,
      ));

      await db.deleteAccount(cashId);

      // Rules/templates survive but no longer point at the dead account.
      expect((await db.getRecurringRules()).single.accountId, isNull);
      expect((await db.getTemplates()).single.accountId, isNull);
    });
  });

  group('ExpenseProvider type-aware aggregates', () {
    test('income and transfers are excluded from spending totals', () async {
      final db = DBService();
      final date = DateTime(2026, 6, 10);
      await db.insertExpense(
          tx(amount: 100, type: DbConstants.txExpense, date: date));
      await db.insertExpense(tx(
          amount: 5000,
          type: DbConstants.txIncome,
          date: date,
          category: 'Salary'));
      await db.insertExpense(
          tx(amount: 300, type: DbConstants.txTransfer, date: date));

      final provider = ExpenseProvider();
      await provider.ensureYearLoaded(2026);

      expect(provider.totalForMonth(2026, 6), 100.0);
      expect(provider.totalForYear(2026), 100.0);
      expect(provider.incomeForMonth(2026, 6), 5000.0);
      expect(provider.incomeForYear(2026), 5000.0);
      expect(provider.categoryTotalsForMonth(2026, 6).containsKey('Salary'),
          isFalse);
      expect(provider.categoryTotalsForYear(2026)['Other'], 100.0);
      expect(provider.spendingForMonth(2026, 6).length, 1);
      // The raw row list still contains everything.
      expect(provider.expensesForMonth(2026, 6).length, 3);
    });
  });

  group('Backup v2', () {
    test('expense toMap/fromMap round-trips type and account links', () {
      final original = tx(
          amount: 42,
          type: DbConstants.txTransfer,
          accountId: 1,
          toAccountId: 2);
      final restored = Expense.fromMap(original.toMap());
      expect(restored.type, DbConstants.txTransfer);
      expect(restored.accountId, 1);
      expect(restored.toAccountId, 2);
    });

    test('legacy expense map without type defaults to expense', () {
      final restored = Expense.fromMap({
        'id': 7,
        'description': 'Old',
        'amount': 10.0,
        'date': DateTime(2024, 1, 1).toIso8601String(),
        'category': 'Food',
        'paymentMode': 'Cash',
      });
      expect(restored.type, DbConstants.txExpense);
      expect(restored.accountId, isNull);
      expect(restored.isExpense, isTrue);
    });
  });
}
