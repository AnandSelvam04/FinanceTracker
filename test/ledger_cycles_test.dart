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
import 'package:finance_tracker/utils/account_ledger.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:finance_tracker/utils/ledger_cycles.dart';

void main() {
  group('ledgerByCycle', () {
    // Statement on the 5th, due on the 25th; today is 20 Mar 2026.
    final now = DateTime(2026, 3, 20);
    AccountLedgerEntry entry(DateTime date, int delta) => AccountLedgerEntry(
        source: Object(), date: date, delta: delta, balanceAfter: 0);

    test('rows fall in the cycle whose statement bills them', () {
      final cycles = ledgerByCycle([
        entry(DateTime(2026, 3, 12, 18), -3000), // open cycle
        entry(DateTime(2026, 3, 6), -2000), // first day of the open cycle
        entry(DateTime(2026, 3, 5, 21), -5000), // the statement day itself
        entry(DateTime(2026, 2, 20), 40000), // bill payment
        entry(DateTime(2026, 2, 6), -1000), // first day of the 5 Mar cycle
        entry(DateTime(2026, 2, 4), -7000), // 5 Feb cycle
      ], statementDay: 5, dueDay: 25, now: now);

      expect(cycles.map((c) => c.statementDate), [
        DateTime(2026, 4, 5),
        DateTime(2026, 3, 5),
        DateTime(2026, 2, 5),
      ]);

      final open = cycles[0];
      expect(open.isOpen, isTrue);
      expect(open.start, DateTime(2026, 3, 6));
      expect(open.charged, 5000);
      expect(open.entries, hasLength(2));

      final march = cycles[1];
      expect(march.isOpen, isFalse);
      expect(march.start, DateTime(2026, 2, 6));
      expect(march.dueDate, DateTime(2026, 3, 25));
      expect(march.charged, 6000);
      expect(march.paidIn, 40000);
      expect(march.entries, hasLength(3));

      expect(cycles[2].charged, 7000);
    });

    test('a due day before the statement day falls next month', () {
      final c = ledgerByCycle([entry(DateTime(2026, 3, 1), -100)],
              statementDay: 20, dueDay: 10, now: now)
          .single;
      expect(c.statementDate, DateTime(2026, 3, 20));
      expect(c.dueDate, DateTime(2026, 4, 10));
      // The 20 Mar statement is generated today, so it is closed.
      expect(c.isOpen, isFalse);
    });

    test('a statement day past a short month clamps to its end', () {
      final c = ledgerByCycle([entry(DateTime(2026, 2, 28, 12), -100)],
              statementDay: 31, dueDay: 20, now: now)
          .single;
      expect(c.statementDate, DateTime(2026, 2, 28));
      expect(c.start, DateTime(2026, 2, 1));
    });

    test('no rows, no cycles', () {
      expect(ledgerByCycle(const [], statementDay: 5, dueDay: 25, now: now),
          isEmpty);
    });
  });

  testWidgets('a card statement can be read by cycle or as one list',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DBService.testFactory = databaseFactoryFfi;
    DBService.dbNameOverride = 'ledger_cycles_test.db';
    final today = DateTime.now();
    // The statement was two days ago, so there is a closed and an open cycle.
    final statement = DateTime(today.year, today.month, today.day - 2);
    final accounts = (await tester.runAsync(() async {
      await DBService().clearAll();
      final id = await DBService().insertAccount(Account(
          name: 'Visa',
          type: 'credit_card',
          statementDay: statement.day,
          dueDay: statement.day));
      Expense spend(String what, int amount, DateTime date) => Expense(
          description: what,
          amount: amount,
          date: date,
          category: 'Shopping',
          paymentMode: 'Credit Card',
          type: DbConstants.txExpense,
          accountId: id);
      await DBService().insertExpense(spend('Billed', 120000,
          DateTime(statement.year, statement.month, statement.day - 3)));
      await DBService().insertExpense(spend('Unbilled', 30000,
          DateTime(statement.year, statement.month, statement.day + 1, 9)));
      final a = AccountProvider();
      await a.fetchAccounts();
      return a;
    }))!;

    tester.view.physicalSize = const Size(1080, 3000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountProvider>.value(value: accounts),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
        ChangeNotifierProvider(create: (_) => InvestmentProvider()),
      ],
      child: MaterialApp(
          home: AccountDetailScreen(account: accounts.accounts.single)),
    ));
    for (var i = 0; i < 20 && find.text('Billed').evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    expect(find.text('By cycle'), findsOneWidget);
    expect(find.text('Current cycle'), findsOneWidget);
    expect(find.textContaining('Statement '), findsOneWidget);
    expect(find.text('Spent ₹300.00'), findsOneWidget);
    expect(find.text('Spent ₹1,200.00'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pump();
    expect(find.text('Current cycle'), findsNothing);
    expect(find.text('Billed'), findsOneWidget);
    expect(find.text('Unbilled'), findsOneWidget);

    await tester.runAsync(() => DBService().clearAll());
  }, timeout: const Timeout(Duration(seconds: 45)));
}
