import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/providers/investment_provider.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/credit_card_summary.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:finance_tracker/widgets/credit_cards_card.dart';

void main() {
  group('creditCardSummaries', () {
    // Statement on the 5th, due on the 25th; today is 20 Mar 2026.
    final now = DateTime(2026, 3, 20);
    final card = Account(
        id: 1,
        name: 'Visa',
        type: 'credit_card',
        statementDay: 5,
        dueDay: 25,
        last4: '5678');

    // 50,000 on the 5 Mar statement (6 Feb – 5 Mar), 12,000 since.
    int spend(int id, DateTime start, DateTime end) {
      if (start == DateTime(2026, 2, 6)) return 50000;
      if (start == DateTime(2026, 3, 6)) return 12000;
      if (start == DateTime(2026, 3, 1)) return 7000; // this month, no cycle
      return 0;
    }

    List<CreditCardSummary> run(
      List<Account> accounts, {
      int paid = 0,
      int? balance = -62000,
    }) =>
        creditCardSummaries(
          accounts: accounts,
          now: now,
          spendInRange: spend,
          paidInRange: (_, __, ___) => paid,
          balanceOf: (_) => balance,
        );

    test('a card with a billing cycle', () {
      final s = run([card]).single;
      expect(s.periodStart, DateTime(2026, 3, 6));
      expect(s.cycleSpend, 12000);
      expect(s.statementAmount, 50000);
      expect(s.dueRemaining, 50000);
      expect(s.daysUntilDue, 5);
      expect(s.owed, 62000);
      expect(s.billPaid, isFalse);
      expect(s.isOverdue, isFalse);
    });

    test('a part payment leaves the rest due; a full one marks it paid', () {
      expect(run([card], paid: 20000).single.dueRemaining, 30000);
      final paid = run([card], paid: 50000, balance: -12000).single;
      expect(paid.dueRemaining, 0);
      expect(paid.billPaid, isTrue);
      expect(paid.owed, 12000);
    });

    test('a card without a billing cycle tracks this month', () {
      final plain = Account(id: 2, name: 'Amex', type: 'credit_card');
      final s = run([plain]).single;
      expect(s.hasCycle, isFalse);
      expect(s.periodStart, DateTime(2026, 3, 1));
      expect(s.cycleSpend, 7000);
      expect(s.statementAmount, 0);
    });

    test('a positive balance is credit, not owed', () {
      final s = run([card], balance: 1500).single;
      expect(s.owed, 0);
      expect(s.credit, 1500);
    });

    test('only credit cards are summarised', () {
      final bank = Account(id: 3, name: 'Bank', type: 'bank');
      expect(run([bank, card]).map((s) => s.account.id), [1]);
    });

    test('cards with a bill to pay come first, soonest due first', () {
      final later = Account(
          id: 4,
          name: 'Alpha',
          type: 'credit_card',
          statementDay: 10,
          dueDay: 30); // 10 Mar statement, due 30 Mar
      final plain = Account(id: 5, name: 'Beta', type: 'credit_card');
      final order = creditCardSummaries(
        accounts: [plain, later, card],
        now: now,
        spendInRange: (id, start, end) => 10000,
        paidInRange: (_, __, ___) => 0,
        balanceOf: (_) => -10000,
      ).map((s) => s.account.name);
      expect(order, ['Visa', 'Alpha', 'Beta']);
    });
  });

  group('CreditCardsCard', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DBService.testFactory = databaseFactoryFfi;
    DBService.dbNameOverride = 'credit_cards_card_test.db';

    Future<void> pumpCard(WidgetTester tester,
        {required List<Account> accounts,
        List<Expense> Function(Map<String, int> ids)? rows}) async {
      final now = DateTime.now();
      final providers = (await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        await DBService().clearAll();
        final ids = <String, int>{};
        for (final a in accounts) {
          ids[a.name] = await DBService().insertAccount(a);
        }
        for (final e in rows?.call(ids) ?? const <Expense>[]) {
          await DBService().insertExpense(e);
        }
        final accountProvider = AccountProvider();
        await accountProvider.fetchAccounts();
        final expenses = ExpenseProvider();
        await expenses.ensureYearsLoaded({now.year, now.year - 1});
        final investments = InvestmentProvider();
        await investments.fetchInvestments();
        return (accountProvider, expenses, investments);
      }))!;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: providers.$1),
          ChangeNotifierProvider.value(value: providers.$2),
          ChangeNotifierProvider.value(value: providers.$3),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: CreditCardsCard(now: now)),
          ),
        ),
      ));
      await tester.pump();
    }

    tearDown(() async {
      await DBService().clearAll();
    });

    testWidgets('hidden with no credit cards', (tester) async {
      await pumpCard(tester,
          accounts: [Account(name: 'Savings', type: 'bank')]);
      expect(find.text('Credit cards'), findsNothing);
    }, timeout: const Timeout(Duration(seconds: 45)));

    testWidgets('shows what went on a card and what is owed', (tester) async {
      final today = DateTime.now();
      await pumpCard(
        tester,
        accounts: [
          Account(name: 'HDFC Regalia', type: 'credit_card', last4: '5678'),
        ],
        rows: (ids) => [
          Expense(
            description: 'SWIGGY',
            amount: 45000,
            date: DateTime(today.year, today.month, 1, 12),
            category: 'Food',
            paymentMode: 'Credit Card',
            type: DbConstants.txExpense,
            accountId: ids['HDFC Regalia'],
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Credit cards'), findsOneWidget);
      expect(find.text('HDFC Regalia ••5678'), findsOneWidget);
      expect(find.text('₹450.00'), findsOneWidget);
      expect(find.text('this month'), findsOneWidget);
      expect(find.text('₹450.00 owed'), findsOneWidget);
      expect(
          find.text('Add statement & due days to track bills'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 45)));

    testWidgets('a billed, unpaid card says what is due', (tester) async {
      final today = DateTime.now();
      // Statement two days ago, due in ~20 days; a purchase before it.
      final statement = DateTime(today.year, today.month, today.day - 2);
      await pumpCard(
        tester,
        accounts: [
          Account(
            name: 'Visa',
            type: 'credit_card',
            statementDay: statement.day,
            dueDay:
                DateTime(statement.year, statement.month, statement.day + 20)
                    .day,
          ),
        ],
        rows: (ids) => [
          Expense(
            description: 'AMAZON',
            amount: 120000,
            date: DateTime(statement.year, statement.month, statement.day - 3),
            category: 'Shopping',
            paymentMode: 'Credit Card',
            type: DbConstants.txExpense,
            accountId: ids['Visa'],
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('₹1,200.00 due'), findsOneWidget);
      expect(find.text('this cycle'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 45)));
  });
}
