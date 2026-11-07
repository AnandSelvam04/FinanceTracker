import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/widgets/reconcile_dialog.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;

  group('reconcileTarget', () {
    final visa = Account(
        id: 1, name: 'Visa', type: 'credit_card', creditLimit: 20000000);
    final rupay =
        Account(id: 2, name: 'RuPay', type: 'credit_card', sharedLimitWith: 1);
    final bank = Account(id: 3, name: 'Bank', type: 'bank');
    final balances = {1: -1000000, 2: -500000, 3: 0};
    int? target(Account a, ReconcileFigure f, int amount) => reconcileTarget(
        account: a,
        figure: f,
        amount: amount,
        accounts: [visa, rupay, bank],
        balanceOf: (x) => balances[x.id]);

    test('a bank account takes the figure as its balance', () {
      expect(target(bank, ReconcileFigure.owed, 1234500), 1234500);
    });

    test('a card owes what the bank says is outstanding', () {
      expect(target(visa, ReconcileFigure.owed, 1200000), -1200000);
    });

    test('an available limit leaves room for the other card on the limit', () {
      // 2,00,000 limit, bank says 1,80,000 left, RuPay owes 5,000:
      // the Visa owes 15,000.
      expect(target(visa, ReconcileFigure.available, 18000000), -1500000);
    });

    test('an available limit needs a limit', () {
      final plain = Account(id: 4, name: 'Amex', type: 'credit_card');
      expect(
          reconcileTarget(
              account: plain,
              figure: ReconcileFigure.available,
              amount: 100,
              accounts: [plain],
              balanceOf: (_) => 0),
          isNull);
    });
  });

  group('setBalance', () {
    setUp(() async {
      DBService.dbNameOverride = 'reconcile_test.db';
      await DBService().clearAll();
    });
    tearDown(() async => DBService().clearAll());

    testWidgets('matching the bank moves only the starting balance',
        (tester) async {
      final provider = (await tester.runAsync(() async {
        final id = await DBService().insertAccount(Account(
            name: 'HDFC Visa', type: 'credit_card', openingBalance: -200000));
        await DBService().insertExpense(Expense(
            description: 'Amazon',
            amount: 1000000,
            date: DateTime(2026, 11, 2),
            category: 'Shopping',
            paymentMode: 'Credit Card',
            accountId: id));
        final p = AccountProvider();
        await p.fetchAccounts();
        return p;
      }))!;
      final card = provider.accounts.single;
      expect(provider.balanceOf(card), -1200000);

      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showReconcileDialog(context, card),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('₹12,000.00 owed'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '11500');
      await tester.pump();
      expect(find.textContaining('moves by ₹500.00'), findsOneWidget);
      await tester.tap(find.text('Match'));
      for (var i = 0;
          i < 40 && find.byType(AlertDialog).evaluate().isNotEmpty;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }

      final updated = provider.accounts.single;
      expect(provider.balanceOf(updated), -1150000);
      expect(updated.openingBalance, -150000);
      // The purchase itself is untouched.
      final rows = await tester.runAsync(() => DBService().getExpenses());
      expect(rows!.single.amount, 1000000);
    });
  });
}
