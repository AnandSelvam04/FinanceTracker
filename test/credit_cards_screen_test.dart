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
import 'package:finance_tracker/services/card_limit_readings.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/credit_card_summary.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:finance_tracker/screens/credit_cards_screen.dart';
import 'package:finance_tracker/utils/billing_cycle.dart';
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

    test('owed breaks down into start, earlier, this cycle and payments', () {
      // 50,000 billed and unpaid, 12,000 since: 62,000 owed.
      final s = run([card]).single;
      expect(s.openingOwed, 0);
      expect(s.carriedFromEarlier, 50000);
      expect(s.owesMoreThanCycle, isTrue);

      // Started with 5,000 owed, paid 20,000 since the statement.
      final started = Account(
          id: 1,
          name: 'Visa',
          type: 'credit_card',
          statementDay: 5,
          dueDay: 25,
          openingBalance: -5000);
      final p = run([started], paid: 20000, balance: -47000).single;
      expect(p.paidThisPeriod, 20000);
      expect(p.openingOwed, 5000);
      expect(p.owedAtPeriodStart, 55000);
      expect(p.carriedFromEarlier, 50000);
      // The parts always add back up to what is owed.
      expect(
          p.openingOwed +
              p.carriedFromEarlier +
              p.cycleSpend -
              p.paidThisPeriod,
          p.owed);
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

  group('shared credit limit', () {
    // A bank's Visa and RuPay cards on one 2,00,000 limit: 10,000 spent on
    // the Visa and 5,000 on the RuPay card leaves 1,85,000 on both.
    final visa = Account(
        id: 1,
        name: 'HDFC Visa',
        type: 'credit_card',
        creditLimit: 20000000,
        last4: '1111');
    final rupay = Account(
        id: 2,
        name: 'HDFC RuPay',
        type: 'credit_card',
        sharedLimitWith: 1,
        last4: '2222');
    final other = Account(
        id: 3, name: 'Scapia', type: 'credit_card', creditLimit: 5000000);
    final balances = {1: -1000000, 2: -500000, 3: -100000};

    List<CreditCardSummary> run(List<Account> accounts) => creditCardSummaries(
          accounts: accounts,
          now: DateTime(2026, 3, 20),
          spendInRange: (_, __, ___) => 0,
          paidInRange: (_, __, ___) => 0,
          balanceOf: (a) => balances[a.id],
        );

    test('both cards use up one limit', () {
      final byName = {
        for (final s in run([visa, rupay, other])) s.account.name: s
      };
      for (final name in ['HDFC Visa', 'HDFC RuPay']) {
        final s = byName[name]!;
        expect(s.isSharedLimit, isTrue);
        expect(s.limit, 20000000);
        expect(s.limitUsed, 1500000);
        expect(s.available, 18500000);
        expect(s.usage, closeTo(0.075, 1e-9));
      }
      // Each card still owes only its own spending.
      expect(byName['HDFC Visa']!.owed, 1000000);
      expect(byName['HDFC RuPay']!.owed, 500000);
      expect(byName['HDFC Visa']!.sharesLimitWith.map((a) => a.id), [2]);
      expect(byName['HDFC RuPay']!.sharesLimitWith.map((a) => a.id), [1]);
      // A card of its own is unaffected.
      final scapia = byName['Scapia']!;
      expect(scapia.isSharedLimit, isFalse);
      expect(scapia.available, 4900000);
    });

    test('a link to a missing or foreign-currency card is ignored', () {
      final orphan = Account(
          id: 4,
          name: 'Orphan',
          type: 'credit_card',
          creditLimit: 100000,
          sharedLimitWith: 99);
      final usd = Account(
          id: 5,
          name: 'USD card',
          type: 'credit_card',
          currency: r'$',
          sharedLimitWith: 1);
      final pools = limitPools([visa, orphan, usd]);
      expect(pools[4]!.isShared, isFalse);
      expect(pools[4]!.limit, 100000);
      expect(pools[5]!.isShared, isFalse);
      expect(pools[1]!.isShared, isFalse);
    });

    test('a chain or a loop of links settles on one holder', () {
      final third = Account(
          id: 6, name: 'Third', type: 'credit_card', sharedLimitWith: 2);
      final pools = limitPools([visa, rupay, third]);
      expect(pools[6]!.holder.id, 1);
      expect(pools[6]!.cards.map((a) => a.id), [1, 2, 6]);

      final a =
          Account(id: 7, name: 'A', type: 'credit_card', sharedLimitWith: 8);
      final b =
          Account(id: 8, name: 'B', type: 'credit_card', sharedLimitWith: 7);
      // Terminates, and each card lands in some pool.
      final loop = limitPools([a, b]);
      expect(loop.keys, containsAll([7, 8]));
    });

    test('the limit comes from another card when the holder has none', () {
      final pool = limitPools([
        Account(id: 1, name: 'Visa', type: 'credit_card'),
        Account(
            id: 2,
            name: 'RuPay',
            type: 'credit_card',
            creditLimit: 300,
            sharedLimitWith: 1),
      ])[1]!;
      expect(pool.limit, 300);
    });
  });

  group('likelyBillPayments', () {
    // Statement 5th, due 25th; today 20 Nov. 50,000 billed, unpaid.
    final now = DateTime(2026, 11, 20);
    final card = Account(
        id: 1,
        name: 'HDFC Visa',
        type: 'credit_card',
        statementDay: 5,
        dueDay: 25);
    final s = creditCardSummaries(
      accounts: [card],
      now: now,
      spendInRange: (_, start, __) =>
          start == DateTime(2026, 10, 6) ? 5000000 : 0,
      paidInRange: (_, __, ___) => 0,
      balanceOf: (_) => -5000000,
    ).single;
    Expense e(String desc, int amount, DateTime date, {int? accountId = 9}) =>
        Expense(
            description: desc,
            amount: amount,
            date: date,
            category: 'Bills',
            paymentMode: 'UPI',
            accountId: accountId);

    test('finds the payment saved as spending', () {
      final found = likelyBillPayments(s, [
        e('CRED', 3000000, DateTime(2026, 11, 8)), // part payment, named
        e('Electricity', 5000000, DateTime(2026, 11, 9)), // exactly the bill
        e('Groceries', 300000, DateTime(2026, 11, 9)),
        e('Amazon', 5000000, DateTime(2026, 11, 9), accountId: 1), // on card
        e('CRED', 5000000, DateTime(2026, 11, 2)), // before the statement
      ]);
      expect(found.map((x) => x.description), ['Electricity', 'CRED']);
    });

    test('nothing to find once the bill is paid', () {
      final paid = creditCardSummaries(
        accounts: [card],
        now: now,
        spendInRange: (_, start, __) =>
            start == DateTime(2026, 10, 6) ? 5000000 : 0,
        paidInRange: (_, __, ___) => 5000000,
        balanceOf: (_) => 0,
      ).single;
      expect(likelyBillPayments(paid, [e('CRED', 5000000, now)]), isEmpty);
    });
  });

  group('statement details', () {
    test('a purchase today: billed on the next statement, due after it', () {
      // Statement 5th, due 25th.
      var w = purchaseWindow(
          statementDay: 5, dueDay: 25, day: DateTime(2026, 11, 7, 15));
      expect(w.statement, DateTime(2026, 12, 5));
      expect(w.due, DateTime(2026, 12, 25));
      expect(w.interestFreeDays, 48);
      // On the statement day itself it is on today's statement.
      w = purchaseWindow(
          statementDay: 5, dueDay: 25, day: DateTime(2026, 11, 5));
      expect(w.statement, DateTime(2026, 11, 5));
      expect(w.interestFreeDays, 20);
      // Due day before the statement day: due the next month.
      w = purchaseWindow(
          statementDay: 20, dueDay: 10, day: DateTime(2026, 11, 7));
      expect(w.due, DateTime(2026, 12, 10));
    });

    CreditCardSummary billed(int statement, {int paid = 0}) =>
        CreditCardSummary(
          account: Account(id: 1, name: 'Visa', type: 'credit_card'),
          periodStart: DateTime(2026, 11, 6),
          cycleSpend: 0,
          owed: statement,
          statementAmount: statement,
          paidSinceStatement: paid,
        );

    test('minimum due: 5% of the bill, at least 200', () {
      expect(billed(5000000).minimumDueEstimate, 250000);
      expect(billed(300000).minimumDueEstimate, 20000);
      expect(billed(15000).minimumDueEstimate, 15000);
      expect(billed(5000000, paid: 100000).minimumDueEstimate, 150000);
      expect(billed(0).minimumDueEstimate, 0);
    });

    test('the best card today gives the longest interest-free credit', () {
      final now = DateTime(2026, 11, 7);
      Account card(int id, int stmt, int due, {int? limit}) => Account(
          id: id,
          name: 'Card $id',
          type: 'credit_card',
          statementDay: stmt,
          dueDay: due,
          creditLimit: limit);
      List<CreditCardSummary> run(List<Account> cards,
              {Map<int, int> balances = const {}}) =>
          creditCardSummaries(
            accounts: cards,
            now: now,
            spendInRange: (_, __, ___) => 0,
            paidInRange: (_, __, ___) => 0,
            balanceOf: (a) => balances[a.id] ?? 0,
          );
      // Statement on the 8th: a purchase today is billed tomorrow. Statement
      // on the 6th: it waits for 6 Dec, due 26 Dec.
      final best = bestCardToday(run([card(1, 8, 28), card(2, 6, 26)]), now);
      expect(best!.account.id, 2);
      // A maxed-out card is not offered.
      expect(
          bestCardToday(
              run([card(1, 8, 28), card(2, 6, 26, limit: 100)],
                  balances: {2: -100}),
              now),
          isNull);
      // One card alone has nothing to compare against.
      expect(bestCardToday(run([card(1, 8, 28)]), now), isNull);
    });
  });

  group('limitTwinSuggestions', () {
    Account card(int id, String name, {int? limit, String? currency}) =>
        Account(
            id: id,
            name: name,
            type: 'credit_card',
            creditLimit: limit,
            currency: currency);

    test('pairs cards from one bank, the one with the limit keeping it', () {
      final s = limitTwinSuggestions([
        card(1, 'HDFC RuPay'),
        card(2, 'HDFC Visa', limit: 100),
        card(3, 'Scapia'),
      ]).single;
      expect(s.holder.id, 2);
      expect(s.other.id, 1);
      expect(s.key, '1-2');
    });

    test('skips different limits, currencies, linked and dismissed pairs', () {
      expect(
          limitTwinSuggestions(
              [card(1, 'HDFC A', limit: 100), card(2, 'HDFC B', limit: 200)]),
          isEmpty);
      expect(
          limitTwinSuggestions(
              [card(1, 'HDFC A'), card(2, 'HDFC B', currency: r'$')]),
          isEmpty);
      expect(
          limitTwinSuggestions([
            card(1, 'HDFC A', limit: 100),
            Account(
                id: 2, name: 'HDFC B', type: 'credit_card', sharedLimitWith: 1),
          ]),
          isEmpty);
      expect(
          limitTwinSuggestions([card(1, 'HDFC A'), card(2, 'HDFC B')],
              dismissed: {'1-2'}),
          isEmpty);
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
        List<Expense> Function(Map<String, int> ids)? rows,
        Future<void> Function()? before}) async {
      final now = DateTime.now();
      final providers = (await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        await before?.call();
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
          i < 60 && find.byType(Dialog).evaluate().isNotEmpty;
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

      // More owed than spent: the breakdown says why.
      await tester.tap(find.text('Why ₹42,000.00 owed when ₹32,000.00 was '
          'spent this month?'));
      await tester.pump();
      expect(find.text('Already owed when you started'), findsOneWidget);
      expect(find.text('₹10,000.00'), findsOneWidget);
      expect(find.textContaining('Spent since 1 '), findsOneWidget);
      expect(find.text('Record a bill payment'), findsOneWidget);
      expect(find.text('Fix starting amount'), findsOneWidget);
      // Nothing recorded before this month, so no double counting to flag.
      expect(find.textContaining('counted twice'), findsNothing);
    }, timeout: const Timeout(Duration(seconds: 45)));

    testWidgets('flags a starting amount that may count purchases twice',
        (tester) async {
      final today = DateTime.now();
      await pumpScreen(
        tester,
        accounts: [
          Account(
              name: 'Scapia', type: 'credit_card', openingBalance: -2000000),
        ],
        rows: (ids) => [
          // Imported from SMS last month, though already in the 20,000.
          spend(1500000, DateTime(today.year, today.month - 1, 10, 12),
              ids['Scapia']),
          spend(
              300000, DateTime(today.year, today.month, 1, 12), ids['Scapia']),
        ],
      );
      await tester.tap(find.textContaining('Why ₹38,000.00 owed'));
      await tester.pump();
      expect(find.text('Spent before this month, not yet paid off'),
          findsOneWidget);
      expect(find.textContaining('counted twice'), findsOneWidget);
      expect(find.textContaining('Record it as a transfer'), findsOneWidget);
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
      // With billing days set, the card says when a purchase today is due.
      expect(find.textContaining('Buy today, pay by', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('days interest-free', findRichText: true),
          findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 45)));

    testWidgets('two cards on one limit show what is left of it on both',
        (tester) async {
      final today = DateTime.now();
      final day = DateTime(today.year, today.month, 1, 12);
      await pumpScreen(
        tester,
        accounts: [
          Account(
              name: 'HDFC Visa', type: 'credit_card', creditLimit: 20000000),
          Account(name: 'HDFC RuPay', type: 'credit_card'),
        ],
        rows: (ids) => [
          spend(1000000, day, ids['HDFC Visa']),
          spend(500000, day, ids['HDFC RuPay']),
        ],
      );

      // Link the RuPay card to the Visa card's limit: "Shared" picks the
      // only other card on its own.
      await tester.tap(find.byTooltip('Set up HDFC RuPay'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shared'));
      await tester.pumpAndSettle();
      // The field now edits the shared limit, filled in from the Visa card.
      expect(find.widgetWithText(TextFormField, 'Shared credit limit (₹)'),
          findsOneWidget);
      expect(find.text('200000.00'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);

      final visa =
          accountProvider.accounts.singleWhere((a) => a.name == 'HDFC Visa');
      final rupay =
          accountProvider.accounts.singleWhere((a) => a.name == 'HDFC RuPay');
      expect(rupay.sharedLimitWith, visa.id);
      expect(rupay.creditLimit, isNull);
      expect(visa.creditLimit, 20000000);

      // One frame for both cards, with one bar: 10,000 + 5,000 of 2,00,000.
      expect(find.text('Shared limit · 2 cards'), findsOneWidget);
      expect(find.text('8% of ₹2,00,000.00 used · ₹1,85,000.00 left'),
          findsOneWidget);
      // Each card still shows what is owed on it.
      expect(find.text('₹10,000.00'), findsWidgets);
      expect(find.text('₹5,000.00'), findsWidgets);
      // The totals count the shared limit once; the group shows it too,
      // with the two cards' combined spend and amount owed.
      expect(find.text('₹1,85,000.00'), findsNWidgets(2));
      expect(find.text('Total owed now'), findsOneWidget);
      expect(find.text('₹15,000.00'), findsWidgets);
    }, timeout: const Timeout(Duration(seconds: 45)));

    testWidgets('two cards from one bank are offered for linking',
        (tester) async {
      await pumpScreen(tester, accounts: [
        Account(
            name: 'Scapia Visa',
            type: 'credit_card',
            creditLimit: 15000000,
            statementDay: 3,
            dueDay: 20),
        Account(name: 'Scapia RuPay', type: 'credit_card'),
      ]);
      expect(
          find.text('Do Scapia Visa and Scapia RuPay share one credit '
              'limit?'),
          findsOneWidget);
      await tester.tap(find.text('Link them'));
      Account named(String name) =>
          accountProvider.accounts.singleWhere((a) => a.name == name);
      // No dialog here for settle to wait on, only its short fixed pause,
      // which a slow machine's database write and refresh can outlast.
      for (var i = 0;
          i < 20 && named('Scapia RuPay').sharedLimitWith == null;
          i++) {
        await settle(tester);
      }

      final visa = named('Scapia Visa');
      final rupay = named('Scapia RuPay');
      expect(rupay.sharedLimitWith, visa.id);
      // The RuPay card picks up the Visa card's billing days.
      expect(rupay.statementDay, 3);
      expect(rupay.dueDay, 20);
      expect(find.textContaining('share one credit limit?'), findsNothing);
      expect(find.text('Shared limit · 2 cards'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 45)));

    testWidgets('"Not shared" hides the suggestion', (tester) async {
      await pumpScreen(tester, accounts: [
        Account(name: 'HDFC Regalia', type: 'credit_card'),
        Account(name: 'HDFC Millennia', type: 'credit_card'),
      ]);
      await tester.tap(find.text('Not shared'));
      await settle(tester);
      expect(find.textContaining('share one credit limit?'), findsNothing);
      expect(accountProvider.accounts.every((a) => a.sharedLimitWith == null),
          isTrue);
    }, timeout: const Timeout(Duration(seconds: 45)));

    testWidgets('a card is added straight onto another card\'s limit',
        (tester) async {
      await pumpScreen(tester, accounts: [
        Account(
            name: 'HDFC Visa',
            type: 'credit_card',
            creditLimit: 20000000,
            statementDay: 5,
            dueDay: 25),
      ]);
      await tester.tap(find.byTooltip('More for HDFC Visa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a card on this limit'));
      await tester.pumpAndSettle();
      expect(
          find.text('Copied from HDFC Visa — change them if this card '
              'bills on other days.'),
          findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Card name'), 'HDFC RuPay');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);

      final visa =
          accountProvider.accounts.singleWhere((a) => a.name == 'HDFC Visa');
      final rupay =
          accountProvider.accounts.singleWhere((a) => a.name == 'HDFC RuPay');
      expect(rupay.sharedLimitWith, visa.id);
      expect(rupay.statementDay, 5);
      expect(rupay.dueDay, 25);
      expect(visa.creditLimit, 20000000);
    }, timeout: const Timeout(Duration(seconds: 45)));

    testWidgets('the bank\'s Avl Lmt from SMS is checked against the app',
        (tester) async {
      final today = DateTime.now();
      await pumpScreen(
        tester,
        before: () => CardLimitReadings.record([
          // The bank says 1,80,000 is left; the app only knows of 10,000.
          LimitReading(last4: '1111', amount: 18000000, at: today),
        ]),
        accounts: [
          Account(
              name: 'HDFC Visa',
              type: 'credit_card',
              creditLimit: 20000000,
              last4: '1111'),
        ],
        rows: (ids) => [
          spend(1000000, DateTime(today.year, today.month, today.day),
              ids['HDFC Visa']),
        ],
      );
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.textContaining('Bank says ₹1,80,000.00 available'),
          findsOneWidget);
      expect(find.textContaining('A purchase may be missing'), findsOneWidget);

      await tester.tap(find.text('Match bank'));
      await tester.pumpAndSettle();
      expect(find.text('Match bank balance'), findsOneWidget);
      expect(find.text('180000.00'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Match'));
      await settle(tester);
      await tester.pump();
      expect(find.textContaining('Matches the bank\'s SMS'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 45)));

    testWidgets('a purchase converted to EMI holds the limit, not the bill',
        (tester) async {
      final today = DateTime.now();
      await pumpScreen(
        tester,
        accounts: [
          Account(
              name: 'HDFC Visa', type: 'credit_card', creditLimit: 20000000),
        ],
        rows: (ids) => [
          spend(6000000, DateTime(today.year, today.month, today.day),
              ids['HDFC Visa']),
        ],
      );
      await tester.tap(find.byTooltip('More for HDFC Visa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Convert a purchase to EMI'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'What was bought'), 'iPhone');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Amount converted (₹)'), '60000');
      await tester.pump();
      expect(find.textContaining('₹10,000.00 a month for 6 months'),
          findsOneWidget);
      expect(find.textContaining('No-cost EMI'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Convert'));
      await settle(tester);

      final plans = await tester.runAsync(() => DBService().getEmiPlans());
      expect(plans!.single.months, 6);
      final card =
          accountProvider.accounts.singleWhere((a) => a.name == 'HDFC Visa');
      expect(accountProvider.balanceOf(card), 0);
      expect(find.text('Includes ₹60,000.00 held for EMIs'), findsOneWidget);
      expect(find.text('30% of ₹2,00,000.00 used · ₹1,40,000.00 left'),
          findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 45)));

    testWidgets('reward points set up on a card show with their value',
        (tester) async {
      final today = DateTime.now();
      await pumpScreen(
        tester,
        accounts: [Account(name: 'Scapia', type: 'credit_card')],
        rows: (ids) => [
          spend(
              1000000, DateTime(today.year, today.month, 1, 12), ids['Scapia']),
        ],
      );
      await tester.tap(find.byTooltip('Set up Scapia'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Points balance now'), '2,000');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Points per ₹100'), '10');
      await tester.enterText(
          find.widgetWithText(TextFormField, '₹ per point'), '0.2');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);

      final card = accountProvider.accounts.single;
      expect(card.rewardPoints, 2000);
      expect(card.rewardRate, 10);
      // Set today, so nothing is estimated on top yet.
      expect(find.textContaining('2,000 points · ≈ ₹400.00'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 45)));

    // A card whose last statement billed 8,015 that the app saw no payment
    // for.
    Future<(Account, int)> billedCard(WidgetTester tester,
        {List<Expense> Function(Map<String, int> ids, CreditCardCycle c)?
            more}) async {
      final today = DateTime.now();
      final cycle =
          computeCreditCardCycle(statementDay: 5, dueDay: 25, now: today);
      await pumpScreen(
        tester,
        accounts: [
          Account(name: 'Savings', type: 'bank'),
          Account(
              name: 'HDFC Visa',
              type: 'credit_card',
              statementDay: 5,
              dueDay: 25),
        ],
        rows: (ids) => [
          spend(801500, cycle.billedCycleStart.add(const Duration(hours: 12)),
              ids['HDFC Visa']),
          ...?more?.call(ids, cycle),
        ],
      );
      final card =
          accountProvider.accounts.singleWhere((a) => a.name == 'HDFC Visa');
      return (card, cycle.statementDate.day);
    }

    testWidgets('a bill paid outside the app can be marked as paid',
        (tester) async {
      await billedCard(tester);
      expect(find.textContaining('₹8,015.00 '), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Mark as paid'));
      await tester.pumpAndSettle();
      expect(find.text('Full ₹8,015.00'), findsOneWidget);
      // No default account here, so it starts as not tracked.
      await tester.tap(find.text('Not tracked in the app'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Savings').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Mark as paid').last);
      await settle(tester);

      expect(find.textContaining('Bill paid'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Mark as paid'), findsNothing);
      final rows = await tester.runAsync(() => DBService().getExpenses());
      final payment = rows!.singleWhere((e) => e.isTransfer);
      final savings =
          accountProvider.accounts.singleWhere((a) => a.name == 'Savings');
      expect(payment.amount, 801500);
      expect(payment.accountId, savings.id);
    }, timeout: const Timeout(Duration(seconds: 45)));

    testWidgets('a payment saved as spending is offered as the bill payment',
        (tester) async {
      await billedCard(tester,
          more: (ids, cycle) => [
                Expense(
                  description: 'CRED',
                  amount: 801500,
                  date: cycle.statementDate.add(const Duration(hours: 12)),
                  category: 'Bills',
                  paymentMode: 'UPI',
                  accountId: ids['Savings'],
                ),
              ]);
      expect(find.textContaining('Is "CRED" ₹8,015.00'), findsOneWidget);
      await tester.tap(find.text('Yes, it\'s the payment'));
      // No dialog here for settle to wait on, only its short fixed pause,
      // which a slow machine's database write and refresh can outlast.
      final paid = find.textContaining('Bill paid');
      for (var i = 0; i < 20 && paid.evaluate().isEmpty; i++) {
        await settle(tester);
      }

      expect(paid, findsOneWidget);
      final rows = await tester.runAsync(() => DBService().getExpenses());
      final cred = rows!.singleWhere((e) => e.description == 'CRED');
      expect(cred.isTransfer, isTrue);
    }, timeout: const Timeout(Duration(seconds: 45)));
  });
}
