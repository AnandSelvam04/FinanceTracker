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
import 'package:finance_tracker/screens/credit_cards_screen.dart';
import 'package:finance_tracker/utils/card_period.dart';

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

  group('credit limit usage', () {
    CreditCardSummary withOwed(int owed, {int? limit = 10000000}) =>
        CreditCardSummary(
          account: Account(
              id: 1, name: 'Visa', type: 'credit_card', creditLimit: limit),
          periodStart: DateTime(2026, 3, 1),
          cycleSpend: 0,
          owed: owed,
        );

    test('share used and what is left', () {
      final s = withOwed(4200000); // 42,000 of 1,00,000
      expect(s.limit, 10000000);
      expect(s.usage, closeTo(0.42, 1e-9));
      expect(s.available, 5800000);
      expect(s.usageLevel, CreditUsageLevel.moderate);
    });

    test('levels change at 30% and 80%', () {
      expect(withOwed(2999999).usageLevel, CreditUsageLevel.low);
      expect(withOwed(3000000).usageLevel, CreditUsageLevel.moderate);
      expect(withOwed(7999999).usageLevel, CreditUsageLevel.moderate);
      expect(withOwed(8000000).usageLevel, CreditUsageLevel.high);
    });

    test('over the limit', () {
      final s = withOwed(11000000);
      expect(s.usage, closeTo(1.1, 1e-9));
      expect(s.available, 0);
      expect(s.usageLevel, CreditUsageLevel.high);
    });

    test('nothing without a limit', () {
      for (final limit in [null, 0]) {
        final s = withOwed(4200000, limit: limit);
        expect(s.limit, isNull);
        expect(s.usage, isNull);
        expect(s.available, isNull);
        expect(s.usageLevel, isNull);
      }
    });
  });

  group('cardRange', () {
    final now = DateTime(2026, 3, 20, 15);
    final cycled = Account(
        id: 1, name: 'Visa', type: 'credit_card', statementDay: 5, dueDay: 25);
    final plain = Account(id: 2, name: 'Amex', type: 'credit_card');

    test('this cycle runs from the day after the last statement', () {
      final r = cardRange(cycled, CardPeriodKind.cycle, now);
      expect(r.start, DateTime(2026, 3, 6));
      expect(r.endExclusive, DateTime(2026, 3, 21));
      expect(r.label, 'Since 6 Mar');
    });

    test('a card without a cycle uses this month for "this cycle"', () {
      final r = cardRange(plain, CardPeriodKind.cycle, now);
      expect(r.start, DateTime(2026, 3, 1));
    });

    test('this month and last month', () {
      final m = cardRange(plain, CardPeriodKind.thisMonth, now);
      expect(m.start, DateTime(2026, 3, 1));
      expect(m.endExclusive, DateTime(2026, 3, 21));
      expect(m.label, 'March 2026');
      final l = cardRange(plain, CardPeriodKind.lastMonth, now);
      expect(l.start, DateTime(2026, 2, 1));
      expect(l.endExclusive, DateTime(2026, 3, 1));
    });

    test('a picked range includes its last day', () {
      final r = cardRange(plain, CardPeriodKind.custom, now,
          customStart: DateTime(2026, 1, 10), customEnd: DateTime(2026, 2, 3));
      expect(r.start, DateTime(2026, 1, 10));
      expect(r.endExclusive, DateTime(2026, 2, 4));
      expect(r.label, '10 Jan – 3 Feb');
    });

    test('last month in January is December', () {
      final r =
          cardRange(plain, CardPeriodKind.lastMonth, DateTime(2026, 1, 5));
      expect(r.start, DateTime(2025, 12, 1));
      expect(r.endExclusive, DateTime(2026, 1, 1));
    });
  });

  group('CreditCardsScreen', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DBService.testFactory = databaseFactoryFfi;
    DBService.dbNameOverride = 'credit_cards_screen_test.db';

    late AccountProvider accountProvider;

    Future<void> pumpScreen(WidgetTester tester,
        {List<Account> accounts = const [],
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
        final a = AccountProvider();
        await a.fetchAccounts();
        final expenses = ExpenseProvider();
        await expenses.ensureYearsLoaded({now.year, now.year - 1});
        final investments = InvestmentProvider();
        await investments.fetchInvestments();
        return (a, expenses, investments);
      }))!;
      accountProvider = providers.$1;
      tester.view.physicalSize = const Size(1080, 3000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: providers.$1),
          ChangeNotifierProvider.value(value: providers.$2),
          ChangeNotifierProvider.value(value: providers.$3),
        ],
        child: MaterialApp(home: CreditCardsScreen(now: now)),
      ));
      await tester.pump();
    }

    /// Lets the dialog's database write land and the dialog close, then
    /// rebuilds. Waits on the dialog itself rather than a fixed time: on a
    /// slow CI machine the save took longer than the old fixed wait, and the
    /// closing dialog's text field was still on screen.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0;
          i < 60 && find.byType(AlertDialog).evaluate().isNotEmpty;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      // The provider's refresh after the save.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
    }

    Expense spend(int amount, DateTime date, int? accountId) => Expense(
          description: 'Purchase',
          amount: amount,
          date: date,
          category: 'Shopping',
          paymentMode: 'Credit Card',
          type: DbConstants.txExpense,
          accountId: accountId,
        );

    tearDown(() async {
      await DBService().clearAll();
    });

    testWidgets('with no cards, offers to add one', (tester) async {
      await pumpScreen(tester,
          accounts: [Account(name: 'Savings', type: 'bank')]);
      expect(find.text('No credit cards yet'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Add a credit card'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Card name'), 'HDFC Regalia');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Credit limit (₹)'), '100000');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);

      final card =
          accountProvider.accounts.singleWhere((a) => a.name == 'HDFC Regalia');
      expect(card.type, 'credit_card');
      expect(card.creditLimit, 10000000);
      expect(find.text('HDFC Regalia'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 45)));

    testWidgets('shows spend, owed and limit, and what is still to set up',
        (tester) async {
      final today = DateTime.now();
      await pumpScreen(
        tester,
        accounts: [
          Account(
              name: 'HDFC Regalia',
              type: 'credit_card',
              creditLimit: 10000000,
              openingBalance: -1000000), // ₹10,000 owed when tracking began
        ],
        rows: (ids) => [
          spend(3200000, DateTime(today.year, today.month, 1, 12),
              ids['HDFC Regalia']),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('₹32,000.00'), findsOneWidget); // spent this cycle
      expect(find.text('₹42,000.00'), findsOneWidget); // owed: 10k + 32k
      expect(find.text('42% of ₹1,00,000.00 used · ₹58,000.00 left'),
          findsOneWidget);
      expect(
          find.text('Add statement & due days, last 4 digits'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 45)));

    testWidgets('the period filter changes what "spent" covers',
        (tester) async {
      final today = DateTime.now();
      await pumpScreen(
        tester,
        accounts: [Account(name: 'Visa', type: 'credit_card')],
        rows: (ids) => [
          spend(70000, DateTime(today.year, today.month, 1, 12), ids['Visa']),
          spend(250000, DateTime(today.year, today.month - 1, 10, 12),
              ids['Visa']),
        ],
      );
      expect(find.text('₹700.00'), findsOneWidget);

      await tester.tap(find.text('Last month'));
      await tester.pump();
      expect(find.text('₹2,500.00'), findsOneWidget);
      expect(find.text('₹700.00'), findsNothing);

      await tester.tap(find.text('This month'));
      await tester.pump();
      expect(find.text('₹700.00'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 45)));

    testWidgets('setting a card up saves its limit, days and opening owed',
        (tester) async {
      await pumpScreen(tester,
          accounts: [Account(name: 'Visa', type: 'credit_card')]);
      await tester.tap(find.byTooltip('Set up Visa'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Last 4 digits'), '5678');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Credit limit (₹)'), '50000');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Statement day'), '5');
      // A due day is needed with a statement day.
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      expect(find.text('Set both days'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Due day'), '25');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Already owed when you start (₹)'),
          '12000');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);

      final card = accountProvider.accounts.single;
      expect(card.last4, '5678');
      expect(card.creditLimit, 5000000);
      expect(card.statementDay, 5);
      expect(card.dueDay, 25);
      expect(card.openingBalance, -1200000);
      // Fully set up: nothing left to add, and the bill is tracked.
      expect(find.textContaining('Add '), findsNothing);
      expect(find.text('24% of ₹50,000.00 used · ₹38,000.00 left'),
          findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 45)));
  });
}
