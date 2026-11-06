import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/screens/spending_calendar_screen.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/currency_format.dart';
import 'package:finance_tracker/utils/daily_spend.dart';
import 'package:finance_tracker/utils/db_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'spending_calendar_test.db';

  Expense e(String description, int amount, DateTime date,
          {String type = DbConstants.txExpense}) =>
      Expense(
          description: description,
          amount: amount,
          date: date,
          category: 'Food',
          paymentMode: 'UPI',
          type: type);

  group('formatMoneyCompact', () {
    tearDown(() {
      CurrencyFormat.symbol = '₹';
      CurrencyFormat.hideAmounts = false;
    });

    test('rupees use k, lakh and crore', () {
      expect(formatMoneyCompact(45000), '450');
      expect(formatMoneyCompact(123400), '1.2k');
      expect(formatMoneyCompact(4500000), '45k');
      expect(formatMoneyCompact(34000000), '3.4L');
      expect(formatMoneyCompact(1100000000), '1.1Cr');
      expect(formatMoneyCompact(200000), '2k');
      expect(formatMoneyCompact(-123400), '-1.2k');
    });

    test('other currencies use k and M', () {
      CurrencyFormat.symbol = '\$';
      expect(formatMoneyCompact(34000000), '340k');
      expect(formatMoneyCompact(250000000), '2.5M');
    });

    test('masked while amounts are hidden', () {
      CurrencyFormat.hideAmounts = true;
      expect(formatMoneyCompact(123400), '•••');
    });
  });

  test('dailySpend nets refunds and skips income and transfers', () {
    final totals = dailySpend([
      e('Lunch', 30000, DateTime(2026, 6, 3)),
      e('Refund', -10000, DateTime(2026, 6, 3)),
      e('Salary', 900000, DateTime(2026, 6, 3), type: DbConstants.txIncome),
      e('Move', 50000, DateTime(2026, 6, 4), type: DbConstants.txTransfer),
      e('Dinner', 20000, DateTime(2026, 6, 9)),
    ], (r) => r.amount);
    expect(totals, {3: 20000, 9: 20000});
  });

  test('spendLevel buckets against the biggest day', () {
    expect(spendLevel(0, 1000), 0);
    expect(spendLevel(-50, 1000), 0);
    expect(spendLevel(100, 1000), 1);
    expect(spendLevel(400, 1000), 2);
    expect(spendLevel(600, 1000), 3);
    expect(spendLevel(1000, 1000), 4);
  });

  testWidgets('shows the month and lists a tapped day', (tester) async {
    final now = DateTime.now();
    await tester.runAsync(() async {
      await DBService().clearAll();
      await DBService().insertExpense(
          e('Groceries', 123400, DateTime(now.year, now.month, 1)));
      await DBService()
          .insertExpense(e('Coffee', 25000, DateTime(now.year, now.month, 1)));
    });
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => ExpenseProvider(),
      child: const MaterialApp(home: SpendingCalendarScreen()),
    ));
    for (var i = 0; i < 20 && find.text('1.5k').evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    // ₹1,234 + ₹250 on the 1st.
    expect(find.text('1.5k'), findsOneWidget);
    expect(find.text('Biggest day'), findsOneWidget);

    await tester.tap(find.text('1.5k'));
    await tester.pump();
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);

    await tester.runAsync(() => DBService().clearAll());
  }, timeout: const Timeout(Duration(seconds: 45)));
}
