import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_tracker/models/budget.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/models/recurring_rule.dart';
import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/providers/budget_provider.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/providers/recurring_provider.dart';
import 'package:finance_tracker/screens/budgets_screen.dart';
import 'package:finance_tracker/screens/expense_list_screen.dart';
import 'package:finance_tracker/screens/recurring_screen.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';

/// Widget tests for the money-critical screens: the numbers people rely on
/// (budget "left to spend", the transactions list, recurring rules) are
/// rendered from real providers backed by an in-memory-ish ffi database, so a
/// UI refactor that broke them would fail here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'widget_flows_test.db';

  final now = DateTime.now();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DBService().clearAll();
  });

  tearDown(() async => DBService().clearAll());

  // Pumps a screen with the given already-populated providers, so the test
  // doesn't race the screen's own initState loads.
  Future<void> pumpScreen(
      WidgetTester tester, Widget screen, List<ChangeNotifierProvider> ps) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: ps,
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Budgets screen shows the overall "left to spend"',
      (tester) async {
    await DBService().upsertBudget(Budget(
        category: Budget.overallCategory,
        amount: 100000, // ₹1000 cap
        year: now.year,
        month: now.month));
    await DBService().insertExpense(Expense(
      description: 'Lunch',
      amount: 30000, // ₹300 spent
      date: now,
      category: 'Food',
      paymentMode: 'UPI',
    ));

    final budgets = BudgetProvider();
    await budgets.fetchBudgets();
    final expenses = ExpenseProvider();
    await expenses.ensureYearLoaded(now.year);

    await pumpScreen(tester, const BudgetsScreen(), [
      ChangeNotifierProvider<BudgetProvider>.value(value: budgets),
      ChangeNotifierProvider<ExpenseProvider>.value(value: expenses),
    ]);

    expect(find.textContaining('Total monthly budget'), findsOneWidget);
    // ₹1000 cap − ₹300 spent = ₹700 left.
    expect(find.textContaining('left'), findsWidgets);
  });

  testWidgets('Transactions list renders a seeded transaction', (tester) async {
    await DBService().insertExpense(Expense(
      description: 'Groceries',
      amount: 12345,
      date: now,
      category: 'Food',
      paymentMode: 'UPI',
    ));

    final expenses = ExpenseProvider();
    await expenses.ensureYearLoaded(now.year);
    final accounts = AccountProvider();
    await accounts.fetchAccounts();

    await pumpScreen(tester, const ExpenseListScreen(), [
      ChangeNotifierProvider<ExpenseProvider>.value(value: expenses),
      ChangeNotifierProvider<AccountProvider>.value(value: accounts),
    ]);

    expect(find.text('Groceries'), findsOneWidget);
  });

  testWidgets('Recurring screen shows a rule and its end date', (tester) async {
    await DBService().insertRecurringRule(RecurringRule(
      description: 'Netflix',
      amount: 19900,
      category: 'Bills',
      frequency: DbConstants.freqMonthly,
      nextDue: DateTime(now.year, now.month, 1),
      endDate: DateTime(now.year + 1, now.month, 1),
    ));

    final recurring = RecurringProvider();
    await recurring.fetchRules();
    final accounts = AccountProvider();
    await accounts.fetchAccounts();

    await pumpScreen(tester, const RecurringScreen(), [
      ChangeNotifierProvider<RecurringProvider>.value(value: recurring),
      ChangeNotifierProvider<AccountProvider>.value(value: accounts),
    ]);

    expect(find.text('Netflix'), findsOneWidget);
    expect(find.textContaining('ends'), findsWidgets);
  });
}
