import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/screens/monthly_summary_screen.dart';
import 'package:finance_tracker/services/db_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'monthly_summary_merchants_test.db';

  testWidgets('lists top merchants and opens their transactions',
      (tester) async {
    final now = DateTime.now();
    Expense e(String description, int amount, int day) => Expense(
        description: description,
        amount: amount,
        date: DateTime(now.year, now.month, day),
        category: 'Food',
        paymentMode: 'UPI');
    final accounts = (await tester.runAsync(() async {
      await DBService().clearAll();
      await DBService().insertExpense(e('Swiggy', 30000, 1));
      await DBService().insertExpense(e('SWIGGY 88213', 20000, 1));
      await DBService().insertExpense(e('Cafe', 10000, 1));
      final a = AccountProvider();
      await a.fetchAccounts();
      return a;
    }))!;

    tester.view.physicalSize = const Size(1080, 4000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountProvider>.value(value: accounts),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
      ],
      child: const MaterialApp(home: MonthlySummaryScreen()),
    ));
    for (var i = 0; i < 20 && find.text('Swiggy').evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    expect(find.text('Top merchants'), findsOneWidget);
    expect(find.text('Swiggy'), findsOneWidget);
    expect(find.text('2 transactions · 83% of spend'), findsOneWidget);
    expect(find.text('Cafe'), findsOneWidget);
    expect(find.text('1 transaction · 17% of spend'), findsOneWidget);

    await tester.tap(find.text('Swiggy'));
    await tester.pumpAndSettle();
    expect(find.text('₹300.00'), findsOneWidget);
    expect(find.text('₹200.00'), findsOneWidget);

    await tester.runAsync(() => DBService().clearAll());
  }, timeout: const Timeout(Duration(seconds: 45)));
}
