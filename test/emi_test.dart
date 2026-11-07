import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/emi_plan.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/services/emi_service.dart';
import 'package:finance_tracker/utils/credit_card_summary.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;

  group('EmiPlan', () {
    EmiPlan plan({int principal = 1000000, int months = 3, int? monthly}) =>
        EmiPlan(
          id: 7,
          cardId: 1,
          loanAccountId: 2,
          description: 'Phone',
          principal: principal,
          months: months,
          monthlyAmount: monthly ?? (principal / months).ceil(),
          firstDate: DateTime(2026, 1, 31),
        );

    test('parts add up to the principal and the interest', () {
      final p = plan(monthly: 350000); // 10,000 over 3 at 3,500
      expect([for (var k = 0; k < 3; k++) p.principalPart(k)],
          [333333, 333333, 333334]);
      expect(p.totalInterest, 50000);
      expect(
          [for (var k = 0; k < 3; k++) p.interestPart(k)]
              .reduce((a, b) => a + b),
          50000);
    });

    test('a no-cost EMI has no interest, even with rounding', () {
      expect(plan().totalInterest, 0);
    });

    test('instalments fall monthly, kept within short months', () {
      final p = plan();
      expect(p.dateOf(0), DateTime(2026, 1, 31));
      expect(p.dateOf(1), DateTime(2026, 2, 28));
      expect(p.dateOf(2), DateTime(2026, 3, 31));
      expect(p.billedBy(DateTime(2026, 2, 27)), 1);
      expect(p.billedBy(DateTime(2026, 12, 1)), 3);
    });
  });

  group('EmiService', () {
    setUp(() async {
      DBService.dbNameOverride = 'emi_test.db';
      await DBService().clearAll();
    });
    tearDown(() async => DBService().clearAll());

    Future<(int, AccountProvider)> phoneOnCard({int monthly = 1000000}) async {
      final card = await DBService().insertAccount(Account(
          name: 'HDFC Visa', type: 'credit_card', creditLimit: 20000000));
      await DBService().insertExpense(Expense(
          description: 'Phone',
          amount: 6000000,
          date: DateTime(2026, 8, 20),
          category: 'Shopping',
          paymentMode: 'Credit Card',
          accountId: card));
      final p = AccountProvider();
      await p.fetchAccounts();
      await EmiService.convert(
        card: p.accountById(card)!,
        description: 'Phone',
        principal: 6000000,
        months: 6,
        monthlyAmount: monthly,
        firstDate: DateTime(2026, 9, 5),
        convertedOn: DateTime(2026, 8, 22),
      );
      return (card, p);
    }

    test('converting moves the purchase off the card; instalments bill it',
        () async {
      final (card, p) = await phoneOnCard();
      // 5 Sep, 5 Oct and 5 Nov are billed by 7 Nov.
      expect(await EmiService.postDue(now: DateTime(2026, 11, 7)), 3);
      expect(await EmiService.postDue(now: DateTime(2026, 11, 7)), 0);
      await p.fetchAccounts();

      final c = p.accountById(card)!;
      final loan = p.accounts.singleWhere((a) => a.isLoan);
      expect(loan.sharedLimitWith, card);
      expect(p.balanceOf(c), -3000000); // three instalments of 10,000
      expect(p.balanceOf(loan), -3000000); // 30,000 still to bill

      // The unpaid principal still holds the limit: 60,000 in all.
      final s = creditCardSummaries(
        accounts: p.accounts,
        now: DateTime(2026, 11, 7),
        spendInRange: (_, __, ___) => 0,
        paidInRange: (_, __, ___) => 0,
        balanceOf: p.balanceOf,
      ).single;
      expect(s.owed, 3000000);
      expect(s.emiBlocked, 3000000);
      expect(s.limitUsed, 6000000);
      expect(s.available, 14000000);
    });

    test('interest is an expense on the card; principal is not', () async {
      await phoneOnCard(monthly: 1050000);
      await EmiService.postDue(now: DateTime(2026, 9, 10));
      final rows = await DBService().getExpenses();
      final interest =
          rows.where((e) => e.category == EmiService.interestCategory);
      expect(interest.single.amount, 50000);
      expect(interest.single.isExpense, isTrue);
    });

    test('deleting the card drops its plans and frees the loan', () async {
      final (card, p) = await phoneOnCard();
      await DBService().deleteAccount(card);
      expect(await DBService().getEmiPlans(), isEmpty);
      final loan =
          (await DBService().getAccounts()).singleWhere((a) => a.isLoan);
      expect(loan.sharedLimitWith, isNull);
    });
  });
}
