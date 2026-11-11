import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/screens/monthly_summary_screen.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/date_format.dart';
import 'package:finance_tracker/utils/db_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'reports_screen_test.db';

  final now = DateTime.now();
  // A year that is over, so its figures don't depend on today's date.
  final lastYear = now.year - 1;

  Expense e(String description, int amount, DateTime date,
          {String category = 'Food', String type = DbConstants.txExpense}) =>
      Expense(
          description: description,
          amount: amount,
          date: date,
          category: category,
          paymentMode: 'UPI',
          type: type);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> pumpReports(WidgetTester tester) async {
    final accounts = (await tester.runAsync(() async {
      final db = DBService();
      await db.clearAll();
      await db.insertExpense(e('Rent', 2000000, DateTime(lastYear, 1, 5)));
      await db.insertExpense(e('Laptop', 6000000, DateTime(lastYear, 3, 9),
          category: 'Shopping'));
      await db.insertExpense(e('Groceries', 400000, DateTime(lastYear, 7, 1)));
      await db.insertExpense(e('Salary', 9000000, DateTime(lastYear, 1, 1),
          category: 'Salary', type: DbConstants.txIncome));
      await db.insertExpense(e('Today lunch', 25000, now));
      final a = AccountProvider();
      await a.fetchAccounts();
      return a;
    }))!;
    tester.view.physicalSize = const Size(1080, 6000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountProvider>.value(value: accounts),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
      ],
      child: const MaterialApp(home: MonthlySummaryScreen()),
    ));
    await settle(tester);
  }

  testWidgets('Year shows the year in review and opens a month from its chart',
      (tester) async {
    await pumpReports(tester);
    await tester.tap(find.text('Year'));
    await settle(tester);
    // Step back to the finished year.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await settle(tester);

    expect(find.text('$lastYear'), findsOneWidget);
    expect(find.text('Month by month'), findsOneWidget);
    expect(find.text('Year in review'), findsOneWidget);
    expect(find.text('Highest spending'), findsOneWidget);
    expect(find.text('March'), findsOneWidget);
    expect(find.text('Lowest spending'), findsOneWidget);
    expect(find.text('July'), findsOneWidget);
    expect(find.textContaining('Laptop ·'), findsOneWidget);
    // Every day of that year but the three with spending.
    final days = DateTime(lastYear + 1).difference(DateTime(lastYear)).inDays;
    expect(find.text('${days - 3}'), findsOneWidget);
    expect(find.textContaining('Expense vs last year'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp('^March: ')));
    await settle(tester);
    expect(find.text('March $lastYear'), findsOneWidget);
    expect(find.text('Year in review'), findsNothing);
    expect(find.textContaining('Expense vs last month'), findsOneWidget);
  });

  testWidgets('Custom starts on the last 30 days', (tester) async {
    await pumpReports(tester);
    await tester.tap(find.text('Custom'));
    await settle(tester);

    final start = DateTime(now.year, now.month, now.day - 29);
    expect(
        find.text('${formatShortDate(start)}  –  '
            '${formatShortDate(DateTime(now.year, now.month, now.day))}'),
        findsOneWidget);
    expect(find.textContaining('Expense vs the 30 days before'),
        findsOneWidget);
    // Only today's lunch falls inside it.
    expect(find.text('Year in review'), findsNothing);
    expect(find.byTooltip('Share as Excel'), findsOneWidget);
  });
}
