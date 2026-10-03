import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/providers/investment_provider.dart';
import 'package:finance_tracker/screens/account_detail_screen.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'account_detail_screen_test.db';

  testWidgets('lists the account\'s rows with a running balance',
      (tester) async {
    final accounts = (await tester.runAsync(() async {
      await DBService().clearAll();
      final id = await DBService().insertAccount(
          Account(name: 'HDFC', type: 'bank', openingBalance: 100000));
      await DBService().insertExpense(Expense(
          description: 'Salary',
          amount: 500000,
          date: DateTime(2026, 9, 1),
          category: 'Salary',
          paymentMode: 'Other',
          type: DbConstants.txIncome,
          accountId: id));
      await DBService().insertExpense(Expense(
          description: 'Groceries',
          amount: 25000,
          date: DateTime(2026, 9, 2),
          category: 'Food',
          paymentMode: 'UPI',
          accountId: id));
      final a = AccountProvider();
      await a.fetchAccounts();
      return a;
    }))!;

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountProvider>.value(value: accounts),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
        ChangeNotifierProvider(create: (_) => InvestmentProvider()),
      ],
      child: MaterialApp(
          home: AccountDetailScreen(account: accounts.accounts.single)),
    ));
    for (var i = 0; i < 20 && find.text('Groceries').evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('Opening balance'), findsOneWidget);
    // 1,000 opening + 5,000 salary − 250 groceries.
    expect(find.text('₹5,750.00'), findsWidgets);
    expect(find.text('₹6,000.00'), findsOneWidget); // after the salary
    expect(find.byTooltip('Edit account'), findsOneWidget);

    await tester.runAsync(() => DBService().clearAll());
  }, timeout: const Timeout(Duration(seconds: 45)));
}
