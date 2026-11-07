import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/screens/loans_screen.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:finance_tracker/utils/debt_summary.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;

  group('debtSummary', () {
    test('a loan: borrowed, repaid and left', () {
      final loan = Account(id: 1, name: 'SBI', type: 'loan');
      // Borrowed 1,00,000 into the bank, repaid 30,000.
      final s =
          debtSummary(loan, -7000000, (inflow: 3000000, outflow: 10000000))!;
      expect(s.total, 10000000);
      expect(s.repaid, 3000000);
      expect(s.outstanding, 7000000);
      expect(s.progress, closeTo(0.3, 1e-9));
      expect(s.settled, isFalse);
    });

    test('a loan from before tracking starts at its opening amount', () {
      final loan = Account(
          id: 1, name: 'Car loan', type: 'loan', openingBalance: -50000000);
      final s = debtSummary(loan, -45000000, (inflow: 5000000, outflow: 0))!;
      expect(s.total, 50000000);
      expect(s.repaid, 5000000);
      expect(s.outstanding, 45000000);
    });

    test('money lent, paid back in full', () {
      final lent = Account(id: 2, name: 'Ravi', type: 'lent');
      final s = debtSummary(lent, 0, (inflow: 500000, outflow: 500000))!;
      expect(s.total, 500000);
      expect(s.repaid, 500000);
      expect(s.settled, isTrue);
    });

    test('other accounts have no debt summary', () {
      expect(debtSummary(Account(id: 3, name: 'Bank', type: 'bank'), 0, null),
          isNull);
    });
  });

  group('LoansScreen', () {
    setUp(() async {
      DBService.dbNameOverride = 'loans_test.db';
      SharedPreferences.setMockInitialValues({});
      await DBService().clearAll();
    });
    tearDown(() async => DBService().clearAll());

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('borrowing into a bank records a transfer and the debt',
        (tester) async {
      final providers = (await tester.runAsync(() async {
        await DBService()
            .insertAccount(Account(name: 'HDFC Savings', type: 'bank'));
        final a = AccountProvider();
        await a.fetchAccounts();
        final e = ExpenseProvider();
        await e.ensureYearsLoaded({DateTime.now().year});
        return (a, e);
      }))!;
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: providers.$1),
          ChangeNotifierProvider.value(value: providers.$2),
        ],
        child: const MaterialApp(home: LoansScreen()),
      ));
      await settle(tester);
      expect(find.text('No loans yet'), findsOneWidget);

      await tester.tap(find.text('I borrowed money'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'From whom, or which loan'),
          'Ravi');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Amount (₹)'), '20000');
      await tester.tap(find.text('Not through an account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HDFC Savings').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);

      final accounts = providers.$1;
      final bank = accounts.accounts.singleWhere((a) => a.type == 'bank');
      final loan = accounts.accounts.singleWhere((a) => a.isLoan);
      expect(loan.name, 'Ravi');
      expect(accounts.balanceOf(bank), 2000000);
      expect(accounts.balanceOf(loan), -2000000);
      final rows = await tester.runAsync(() => DBService().getExpenses());
      expect(rows!.single.type, DbConstants.txTransfer);
      expect(rows.single.accountId, loan.id);
      expect(rows.single.toAccountId, bank.id);

      expect(find.text('I owe'), findsWidgets);
      expect(find.text('₹20,000.00'), findsWidgets);
      expect(find.text('₹0.00 repaid of ₹20,000.00 borrowed'), findsOneWidget);
      expect(find.text('Record repayment'), findsOneWidget);
    });

    testWidgets('a repayment counts toward the loan', (tester) async {
      final providers = (await tester.runAsync(() async {
        final bank = await DBService()
            .insertAccount(Account(name: 'Bank', type: 'bank'));
        final lent = await DBService()
            .insertAccount(Account(name: 'Priya', type: 'lent'));
        Expense t(int amt, int from, int to) => Expense(
            description: 'x',
            amount: amt,
            date: DateTime(2026, 10, 1),
            category: 'Transfer',
            paymentMode: 'Other',
            type: DbConstants.txTransfer,
            accountId: from,
            toAccountId: to);
        await DBService().insertExpense(t(1000000, bank, lent));
        await DBService().insertExpense(t(400000, lent, bank));
        final a = AccountProvider();
        await a.fetchAccounts();
        return (a, ExpenseProvider());
      }))!;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: providers.$1),
          ChangeNotifierProvider.value(value: providers.$2),
        ],
        child: const MaterialApp(home: LoansScreen()),
      ));
      await settle(tester);
      expect(find.text('Owed to me'), findsWidgets);
      expect(find.text('₹6,000.00'), findsWidgets);
      expect(
          find.text('₹4,000.00 paid back of ₹10,000.00 lent'), findsOneWidget);
      expect(find.text('Got paid back'), findsOneWidget);
    });
  });
}
