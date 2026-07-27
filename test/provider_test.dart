import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Initialize sqflite for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  // Isolate this file's database so concurrently running test files
  // can't clear each other's data (they all share one ffi process).
  DBService.dbNameOverride = 'provider_test.db';

  group('ExpenseProvider Tests', () {
    late ExpenseProvider provider;

    setUp(() async {
      // We don't need to manually open the DB here because DBService handles it.
      // Just ensure we start with a clean state.
      await DBService().clearAll();
      provider = ExpenseProvider();
    });

    tearDown(() async {
      // Optional: Close DB if needed, but DBService keeps it open.
      // We can clear it again to be safe.
      await DBService().clearAll();
    });

    test('Add and fetch expenses', () async {
      final now = DateTime.now();
      final expense = Expense(
        description: 'Test Expense',
        amount: 10000, // minor units = 100.00
        date: now,
        category: 'Food',
        paymentMode: 'Cash',
      );

      await DBService().insertExpense(expense);
      // Use ensureYearLoaded instead of fetchExpenses
      await provider.ensureYearLoaded(now.year);

      expect(provider.expenses.length, 1);
      expect(provider.expenses.first.description, 'Test Expense');
    });

    test('Total for month', () async {
      final now = DateTime.now();
      final expense1 = Expense(
        description: 'Exp1',
        amount: 5000,
        date: now,
        category: 'Food',
        paymentMode: 'Cash',
      );
      final expense2 = Expense(
        description: 'Exp2',
        amount: 3000,
        date: now,
        category: 'Transport',
        paymentMode: 'Card',
      );

      await DBService().insertExpense(expense1);
      await DBService().insertExpense(expense2);
      
      await provider.ensureYearLoaded(now.year);

      final total = provider.totalForMonth(now.year, now.month);
      expect(total, 8000);
    });

    test('Category totals for year', () async {
      final now = DateTime.now();
      final expense = Expense(
        description: 'Exp',
        amount: 10000,
        date: now,
        category: 'Food',
        paymentMode: 'Cash',
      );

      await DBService().insertExpense(expense);

      await provider.ensureYearLoaded(now.year);

      final totals = provider.categoryTotalsForYear(now.year);
      expect(totals['Food'], 10000);
    });
  });

  group('ExpenseProvider foreign-currency totals', () {
    // A ₹ base with one $ account at 83. Amounts are stored in the *source
    // account's* currency, so every base-currency total has to convert.
    // Without this a $100 expense was counted as ₹100 and rendered with the ₹
    // symbol, disagreeing with the net-worth card on the same screen.
    late ExpenseProvider provider;
    late int inrAccount;
    late int usdAccount;
    final date = DateTime(2026, 5, 10);

    setUp(() async {
      await DBService().clearAll();
      inrAccount = await DBService()
          .insertAccount(Account(name: 'Cash', type: 'cash'));
      usdAccount = await DBService().insertAccount(
          Account(name: 'US', type: 'bank', currency: '\$', rate: 83));
      provider = ExpenseProvider()
        ..syncAccountRates({inrAccount: 1.0, usdAccount: 83.0});
    });

    tearDown(() async => DBService().clearAll());

    Future<void> add(String type, int amount, int? accountId,
        {String category = 'Food'}) async {
      await DBService().insertExpense(Expense(
        description: 'x',
        amount: amount,
        date: date,
        category: category,
        paymentMode: 'Cash',
        type: type,
        accountId: accountId,
      ));
    }

    test('month and year expense totals convert at the account rate',
        () async {
      await add(DbConstants.txExpense, 50000, inrAccount); // ₹500.00
      await add(DbConstants.txExpense, 10000, usdAccount); // $100 -> ₹8,300
      await provider.ensureYearLoaded(2026);

      expect(provider.totalForMonth(2026, 5), 50000 + 830000);
      expect(provider.totalForYear(2026), 50000 + 830000);
    });

    test('income totals convert too', () async {
      await add(DbConstants.txIncome, 10000, usdAccount);
      await provider.ensureYearLoaded(2026);

      expect(provider.incomeForMonth(2026, 5), 830000);
      expect(provider.incomeForYear(2026), 830000);
    });

    test('category totals convert per row', () async {
      await add(DbConstants.txExpense, 10000, usdAccount, category: 'Food');
      await add(DbConstants.txExpense, 20000, inrAccount, category: 'Food');
      await add(DbConstants.txExpense, 1000, usdAccount, category: 'Travel');
      await provider.ensureYearLoaded(2026);

      expect(provider.categoryTotalsForMonth(2026, 5),
          {'Food': 830000 + 20000, 'Travel': 83000});
      expect(provider.categoryTotalsForYear(2026),
          {'Food': 830000 + 20000, 'Travel': 83000});
    });

    test('rows with no account, or an unknown one, stay at rate 1', () async {
      await add(DbConstants.txExpense, 10000, null);
      await add(DbConstants.txExpense, 10000, 9999);
      await provider.ensureYearLoaded(2026);

      expect(provider.totalForMonth(2026, 5), 20000);
    });

    test('a provider with no rates synced behaves as before', () async {
      await add(DbConstants.txExpense, 12345, usdAccount);
      final unsynced = ExpenseProvider();
      await unsynced.ensureYearLoaded(2026);

      expect(unsynced.totalForMonth(2026, 5), 12345);
    });

    test('syncAccountRates only notifies when a rate actually changes', () {
      var notifications = 0;
      provider.addListener(() => notifications++);

      provider.syncAccountRates({inrAccount: 1.0, usdAccount: 83.0});
      expect(notifications, 0, reason: 'identical rates should be a no-op');

      provider.syncAccountRates({inrAccount: 1.0, usdAccount: 84.0});
      expect(notifications, 1);
    });
  });
}
