import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/budget.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/models/investment.dart';
import 'package:finance_tracker/models/recurring_rule.dart';
import 'package:finance_tracker/models/savings_goal.dart';
import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/providers/budget_provider.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/providers/goal_provider.dart';
import 'package:finance_tracker/providers/investment_provider.dart';
import 'package:finance_tracker/providers/recurring_provider.dart';
import 'package:finance_tracker/providers/settings_provider.dart';
import 'package:finance_tracker/providers/template_provider.dart';
import 'package:finance_tracker/screens/account_detail_screen.dart';
import 'package:finance_tracker/screens/accounts_screen.dart';
import 'package:finance_tracker/screens/add_expense_screen.dart';
import 'package:finance_tracker/screens/add_investment_screen.dart';
import 'package:finance_tracker/screens/add_transfer_screen.dart';
import 'package:finance_tracker/screens/budgets_screen.dart';
import 'package:finance_tracker/screens/cashflow_screen.dart';
import 'package:finance_tracker/screens/categories_screen.dart';
import 'package:finance_tracker/screens/category_trends_screen.dart';
import 'package:finance_tracker/screens/expense_list_screen.dart';
import 'package:finance_tracker/screens/goals_screen.dart';
import 'package:finance_tracker/screens/home_screen.dart';
import 'package:finance_tracker/screens/investment_type_screen.dart';
import 'package:finance_tracker/screens/investments_screen.dart';
import 'package:finance_tracker/screens/monthly_summary_screen.dart';
import 'package:finance_tracker/screens/more_screen.dart';
import 'package:finance_tracker/screens/onboarding_screen.dart';
import 'package:finance_tracker/screens/recurring_screen.dart';
import 'package:finance_tracker/screens/settings_screen.dart';
import 'package:finance_tracker/screens/tutorial_screen.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';

/// Renders every main screen at a 360dp phone width, with long names and
/// large amounts, at the default and a large (1.3x) system text size, and
/// fails on any layout error such as a RenderFlex overflow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'layout_sweep_test.db';

  final now = DateTime.now();
  late Account card;

  // Real glyph widths: the default test font draws every character as a
  // full em square, which overstates overflows by roughly 2x.
  setUpAll(() async {
    for (final family in ['Roboto', '']) {
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(
            File('assets/fonts/FreeSans.ttf').readAsBytesSync())))
        ..addFont(Future.value(ByteData.sublistView(
            File('assets/fonts/FreeSansBold.ttf').readAsBytesSync())));
      await loader.load();
    }
  });

  Future<void> seed() async {
    SharedPreferences.setMockInitialValues({});
    final db = DBService();
    await db.clearAll();
    final bank = await db.insertAccount(Account(
        name: 'State Bank of India Savings Account',
        type: 'bank',
        openingBalance: 123456789));
    final cardId = await db.insertAccount(Account(
        name: 'HDFC Regalia Gold Credit Card',
        type: 'credit',
        statementDay: 5,
        dueDay: 25));
    card = Account(
        id: cardId,
        name: 'HDFC Regalia Gold Credit Card',
        type: 'credit',
        statementDay: 5,
        dueDay: 25);
    for (var i = 0; i < 12; i++) {
      final d = DateTime(now.year, now.month - i, 3);
      await db.insertExpense(Expense(
          description: 'Monthly salary credited from employer',
          amount: 18500000,
          date: d,
          category: 'Salary',
          paymentMode: 'Bank',
          type: DbConstants.txIncome,
          accountId: bank));
      await db.insertExpense(Expense(
          description: 'Big Bazaar Hypermarket groceries and household',
          amount: 1234567,
          date: d,
          category: 'Groceries & Household Supplies',
          paymentMode: 'Credit Card',
          accountId: cardId,
          note: 'Split with flatmates, settle at month end'));
      await db.insertExpense(Expense(
          description: 'House rent',
          amount: 4500000,
          date: d,
          category: 'Rent',
          paymentMode: 'UPI',
          accountId: bank));
      await db.insertExpense(Expense(
          description: 'Card bill',
          amount: 1234567,
          date: d,
          category: 'Transfer',
          paymentMode: 'Bank',
          type: DbConstants.txTransfer,
          accountId: bank,
          toAccountId: cardId));
    }
    await db.insertBudget(Budget(
        category: 'Groceries & Household Supplies',
        amount: 1000000,
        year: now.year,
        month: now.month));
    await db.insertBudget(Budget(
        category: Budget.overallCategory,
        amount: 9000000,
        year: now.year,
        month: now.month));
    await db.insertInvestment(Investment(
        name: 'Parag Parikh Flexi Cap Fund Direct Growth',
        amount: 99999900,
        date: now,
        type: 'Mutual Funds'));
    await db.insertRecurringRule(RecurringRule(
        description: 'Netflix Premium 4K subscription',
        amount: 64900,
        category: 'Entertainment & Subscriptions',
        frequency: 'monthly',
        nextDue: DateTime(now.year, now.month, now.day + 2),
        accountId: cardId));
    await db.insertGoal(SavingsGoal(
        name: 'Emergency fund for six months of expenses',
        target: 60000000,
        saved: 12345600,
        targetDate: DateTime(now.year + 1, 12, 31)));
  }

  final screens = <String, Widget Function()>{
    'Home': () => const HomeScreen(),
    'ExpenseList': () => const ExpenseListScreen(),
    'Accounts': () => const AccountsScreen(),
    'AccountDetail': () => AccountDetailScreen(account: card),
    'Budgets': () => const BudgetsScreen(),
    'Cashflow': () => const CashflowScreen(),
    'Categories': () => const CategoriesScreen(),
    'CategoryTrends': () => const CategoryTrendsScreen(),
    'Goals': () => const GoalsScreen(),
    'Investments': () => const InvestmentsScreen(),
    'InvestmentType': () => const InvestmentTypeScreen(type: 'Mutual Funds'),
    'MonthlySummary': () => const MonthlySummaryScreen(),
    'More': () => const MoreScreen(),
    'Recurring': () => const RecurringScreen(),
    'Settings': () => const SettingsScreen(),
    'AddExpense': () => const AddExpenseScreen(),
    'AddTransfer': () => const AddTransferScreen(),
    'AddInvestment': () => const AddInvestmentScreen(),
    'Onboarding': () => const OnboardingScreen(),
    'Tutorial': () => const TutorialScreen(),
  };

  for (final scale in [1.0, 1.3]) {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} @ ${scale}x', (tester) async {
        final settings = (await tester.runAsync(() async {
          await seed();
          final s = SettingsProvider();
          await s.load();
          return s;
        }))!;
        tester.view.physicalSize = const Size(360 * 3, 780 * 3);
        tester.view.devicePixelRatio = 3;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final errors = <String>[];
        final old = FlutterError.onError;
        FlutterError.onError = (d) {
          final s = d.toString();
          final loc = RegExp(r'lib/[\w/]+\.dart:\d+').firstMatch(s)?.group(0);
          errors.add('${d.exceptionAsString().split('\n').first} @ $loc');
        };
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => InvestmentProvider()),
            ChangeNotifierProvider(create: (_) => BudgetProvider()),
            ChangeNotifierProxyProvider<InvestmentProvider, AccountProvider>(
              create: (_) => AccountProvider(),
              update: (_, inv, acc) =>
                  (acc ?? AccountProvider())..syncInvestments(inv.investments),
            ),
            ChangeNotifierProxyProvider<AccountProvider, ExpenseProvider>(
              create: (_) => ExpenseProvider(),
              update: (_, acc, exp) => (exp ?? ExpenseProvider())
                ..syncAccountRates(acc.ratesByAccount),
            ),
            ChangeNotifierProvider(create: (_) => RecurringProvider()),
            ChangeNotifierProvider(create: (_) => TemplateProvider()),
            ChangeNotifierProvider(create: (_) => GoalProvider()),
            ChangeNotifierProvider.value(value: settings),
          ],
          child: MaterialApp(home: entry.value()),
        ));
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        // Scroll down the main scrollable so lazily built rows lay out too.
        final scrollables = find.byType(Scrollable);
        if (scrollables.evaluate().isNotEmpty) {
          for (var i = 0; i < 6; i++) {
            await tester.drag(scrollables.first, const Offset(0, -500),
                warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump();
        FlutterError.onError = old;
        final e = tester.takeException();
        if (e != null) errors.add('exception: $e');
        expect(errors.toSet(), isEmpty);
      }, timeout: const Timeout(Duration(seconds: 60)));
    }
  }
}
