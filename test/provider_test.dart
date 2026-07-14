import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Initialize sqflite for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;

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
}
