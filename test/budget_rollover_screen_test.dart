import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/budget.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/budget_provider.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/providers/settings_provider.dart';
import 'package:finance_tracker/screens/budgets_screen.dart';
import 'package:finance_tracker/services/db_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'budget_rollover_screen_test.db';

  Future<void> pumpBudgets(WidgetTester tester,
      {required bool rollover}) async {
    final now = DateTime.now();
    final last = DateTime(now.year, now.month - 1);
    final settings = (await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({'budgetRollover': rollover});
      await DBService().clearAll();
      for (final d in [last, now]) {
        await DBService().upsertBudget(Budget(
            category: 'Food', amount: 100000, year: d.year, month: d.month));
      }
      // ₹400 of last month's ₹1,000 spent: ₹600 rolls over.
      await DBService().insertExpense(Expense(
          description: 'Groceries',
          amount: 40000,
          date: DateTime(last.year, last.month, 10),
          category: 'Food',
          paymentMode: 'UPI'));
      final s = SettingsProvider();
      await s.load();
      return s;
    }))!;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BudgetProvider()),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: const MaterialApp(home: BudgetsScreen()),
    ));
    for (var i = 0; i < 20 && find.text('Food').evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    // Let the previous year's load (for a January view) settle too.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }

  testWidgets('with rollover on, last month\'s unspent budget is added',
      (tester) async {
    await pumpBudgets(tester, rollover: true);
    expect(tester.takeException(), isNull);
    expect(find.text('₹0.00 of ₹1,600'), findsOneWidget);
    expect(find.text('₹600 rolled over'), findsOneWidget);
    await tester.runAsync(() => DBService().clearAll());
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('with rollover off, the cap is as set', (tester) async {
    await pumpBudgets(tester, rollover: false);
    expect(find.text('₹0.00 of ₹1,000'), findsOneWidget);
    expect(find.textContaining('rolled over'), findsNothing);
    await tester.runAsync(() => DBService().clearAll());
  }, timeout: const Timeout(Duration(seconds: 45)));
}
