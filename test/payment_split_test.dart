import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/screens/monthly_summary_screen.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:finance_tracker/utils/payment_split.dart';

void main() {
  final card = Account(id: 1, name: 'HDFC Card', type: 'credit_card');
  final card2 = Account(id: 2, name: 'ICICI Card', type: 'credit_card');
  final bank = Account(id: 3, name: 'SBI Savings', type: 'bank');
  final wallet = Account(id: 4, name: 'Wallet', type: 'cash');
  final byId = {
    for (final a in [card, card2, bank, wallet]) a.id: a
  };
  Account? lookup(int? id) => byId[id];

  Expense row(int amount, {int? accountId, String mode = 'Other'}) => Expense(
        description: 'x',
        amount: amount,
        date: DateTime(2026, 3, 10),
        category: 'Food',
        paymentMode: mode,
        type: DbConstants.txExpense,
        accountId: accountId,
      );

  group('payMethodOf', () {
    test('anything on a credit-card account is card spending', () {
      expect(payMethodOf(row(1, accountId: 1, mode: 'UPI'), card),
          PayMethod.creditCard);
    });

    test('otherwise the payment mode decides, then the account type', () {
      expect(
          payMethodOf(row(1, mode: 'Credit Card'), null), PayMethod.creditCard);
      expect(
          payMethodOf(row(1, accountId: 3, mode: 'UPI'), bank), PayMethod.upi);
      expect(payMethodOf(row(1, accountId: 3, mode: 'Cash'), bank),
          PayMethod.cash);
      expect(payMethodOf(row(1, mode: 'Debit Card'), null), PayMethod.bank);
      expect(payMethodOf(row(1, accountId: 3), bank), PayMethod.bank);
      expect(payMethodOf(row(1, accountId: 4), wallet), PayMethod.cash);
      expect(payMethodOf(row(1), null), PayMethod.other);
    });
  });

  group('paymentSplit', () {
    test('groups by method, largest first, with each card under cards', () {
      final split = paymentSplit([
        row(40000, accountId: 1),
        row(20000, accountId: 2),
        row(10000, mode: 'Credit Card'), // a card with no account
        row(25000, accountId: 3, mode: 'UPI'),
        row(5000, mode: 'Cash'),
      ], (e) => e.amount, lookup);

      expect(split.map((m) => m.method),
          [PayMethod.creditCard, PayMethod.upi, PayMethod.cash]);
      final cards = split.first;
      expect(cards.total, 70000);
      expect(cards.parts.map((p) => p.accountId), [1, 2, null]);
      expect(cards.parts.map((p) => p.total), [40000, 20000, 10000]);
    });

    test('refunds come off, and what nets to nothing is left out', () {
      final split = paymentSplit([
        row(40000, accountId: 1),
        row(-15000, accountId: 1), // refund on the card
        row(5000, accountId: 2),
        row(-5000, accountId: 2), // fully refunded
      ], (e) => e.amount, lookup);
      expect(split.single.total, 25000);
      expect(split.single.parts.map((p) => p.accountId), [1]);
    });

    test('income and transfers are not spending', () {
      final split = paymentSplit([
        Expense(
            description: 'Salary',
            amount: 100000,
            date: DateTime(2026, 3, 1),
            category: 'Salary',
            paymentMode: '',
            type: DbConstants.txIncome,
            accountId: 3),
        Expense(
            description: 'Bill',
            amount: 30000,
            date: DateTime(2026, 3, 1),
            category: 'Transfer',
            paymentMode: '',
            type: DbConstants.txTransfer,
            accountId: 3,
            toAccountId: 1),
      ], (e) => e.amount, lookup);
      expect(split, isEmpty);
    });
  });

  testWidgets('the monthly summary shows how the month was paid',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DBService.testFactory = databaseFactoryFfi;
    DBService.dbNameOverride = 'payment_split_test.db';
    final now = DateTime.now();
    final accounts = (await tester.runAsync(() async {
      await DBService().clearAll();
      final cardId = await DBService()
          .insertAccount(Account(name: 'HDFC Card', type: 'credit_card'));
      final bankId = await DBService()
          .insertAccount(Account(name: 'SBI Savings', type: 'bank'));
      Expense e(int amount, int? accountId, String mode) => Expense(
          description: 'x',
          amount: amount,
          date: DateTime(now.year, now.month, 1, 10),
          category: 'Food',
          paymentMode: mode,
          accountId: accountId);
      await DBService().insertExpense(e(60000, cardId, 'Credit Card'));
      await DBService().insertExpense(e(30000, bankId, 'UPI'));
      await DBService().insertExpense(e(10000, null, 'Cash'));
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
    for (var i = 0;
        i < 20 && find.text('How you paid').evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    expect(find.text('How you paid'), findsOneWidget);
    expect(find.text('Credit cards'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('HDFC Card'), findsOneWidget);
    expect(find.text('UPI'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    expect(find.text('SBI Savings'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('10%'), findsOneWidget);

    await tester.runAsync(() => DBService().clearAll());
  }, timeout: const Timeout(Duration(seconds: 45)));
}
