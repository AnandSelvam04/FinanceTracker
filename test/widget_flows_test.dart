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
///
/// Note on `tester.runAsync`: a `testWidgets` body runs inside flutter_test's
/// fake-async zone, where the real background-isolate I/O that
/// sqflite_common_ffi uses never completes — so `await`-ing a database call
/// directly in the body hangs the whole test (the identical calls pass in the
/// other, plain `test()`, files). All database and provider loading is
/// therefore done inside `tester.runAsync`, which runs in the real async zone;
/// only the pumping and the assertions stay in the fake zone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'widget_flows_test.db';

  final now = DateTime.now();

  // Clear only in setUp (a plain callback that runs in the real async zone,
  // so ffi completes), never in a tearDown: a tearDown runs while the screen
  // from the just-finished test is still mounted, which can race the screen's
  // own initState load. This mirrors the working pattern in widget_test.dart.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DBService().clearAll();
  });

  // Pumps a screen with the given already-populated providers, so the test
  // doesn't race the screen's own initState loads.
  //
  // Deliberately NOT pumpAndSettle: these screens keep scheduling frames
  // (entrance animations, and screens whose providers keep a spinner/ticker
  // alive), so pumpAndSettle never returns — see widget_test.dart. The data
  // is already in the providers, so a couple of fixed pumps render it, and
  // the short duration lets the finite entrance animation finish.
  Future<void> pumpScreen(
      WidgetTester tester, Widget screen, List<ChangeNotifierProvider> ps) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: ps,
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  // Unmounts whatever is on screen so the widget (and its providers'
  // listeners / any open database handle) is disposed before the test ends.
  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  // A hard safety net: no matter what a screen does under the test binding,
  // a single test can never again stall the whole suite for minutes.
  const testTimeout = Timeout(Duration(seconds: 45));

  testWidgets('Budgets screen shows the overall "left to spend"',
      (tester) async {
    final (budgets, expenses) = (await tester.runAsync(() async {
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
      final b = BudgetProvider();
      await b.fetchBudgets();
      final e = ExpenseProvider();
      await e.ensureYearLoaded(now.year);
      return (b, e);
    }))!;

    await pumpScreen(tester, const BudgetsScreen(), [
      ChangeNotifierProvider<BudgetProvider>.value(value: budgets),
      ChangeNotifierProvider<ExpenseProvider>.value(value: expenses),
    ]);

    expect(find.textContaining('Total monthly budget'), findsOneWidget);
    // ₹1000 cap − ₹300 spent = ₹700 left.
    expect(find.textContaining('left'), findsWidgets);
    await teardownTree(tester);
  }, timeout: testTimeout);

  testWidgets('Transactions list renders a seeded transaction', (tester) async {
    final (expenses, accounts) = (await tester.runAsync(() async {
      await DBService().insertExpense(Expense(
        description: 'Groceries',
        amount: 12345,
        date: now,
        category: 'Food',
        paymentMode: 'UPI',
      ));
      final e = ExpenseProvider();
      await e.ensureYearLoaded(now.year);
      final a = AccountProvider();
      await a.fetchAccounts();
      return (e, a);
    }))!;

    await pumpScreen(tester, const ExpenseListScreen(), [
      ChangeNotifierProvider<ExpenseProvider>.value(value: expenses),
      ChangeNotifierProvider<AccountProvider>.value(value: accounts),
    ]);

    expect(find.text('Groceries'), findsOneWidget);
    await teardownTree(tester);
  }, timeout: testTimeout);

  testWidgets('Recurring screen shows a rule and its end date', (tester) async {
    final (recurring, accounts) = (await tester.runAsync(() async {
      await DBService().insertRecurringRule(RecurringRule(
        description: 'Netflix',
        amount: 19900,
        category: 'Bills',
        frequency: DbConstants.freqMonthly,
        nextDue: DateTime(now.year, now.month, 1),
        endDate: DateTime(now.year + 1, now.month, 1),
      ));
      final r = RecurringProvider();
      await r.fetchRules();
      final a = AccountProvider();
      await a.fetchAccounts();
      return (r, a);
    }))!;

    await pumpScreen(tester, const RecurringScreen(), [
      ChangeNotifierProvider<RecurringProvider>.value(value: recurring),
      ChangeNotifierProvider<AccountProvider>.value(value: accounts),
    ]);

    expect(find.text('Netflix'), findsOneWidget);
    expect(find.textContaining('ends'), findsWidgets);
    await teardownTree(tester);
  }, timeout: testTimeout);
}
