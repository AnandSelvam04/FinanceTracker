import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/utils/dashboard_insights.dart';
import 'package:finance_tracker/utils/db_constants.dart';

Expense spend(String category, int amount, DateTime date,
        {String description = ''}) =>
    Expense(
        description: description,
        amount: amount,
        date: date,
        category: category,
        paymentMode: 'UPI');

String money(int minor) => '₹${(minor / 100).round()}';

List<Insight> insights({
  required DateTime now,
  int? year,
  int? month,
  required List<Expense> thisMonth,
  List<Expense> lastMonth = const [],
  int income = 0,
  int cap = 0,
  int limit = 5,
}) =>
    dashboardInsights(
      year: year ?? now.year,
      month: month ?? now.month,
      now: now,
      thisMonth: thisMonth,
      lastMonth: lastMonth,
      baseAmountOf: (e) => e.amount,
      income: income,
      overallCap: cap,
      money: money,
      limit: limit,
    );

void main() {
  final now = DateTime(2026, 6, 15, 10);

  group('dashboardInsights', () {
    test('nothing spent, nothing to say', () {
      expect(insights(now: now, thisMonth: const []), isEmpty);
    });

    test('forecasts the month ending under budget', () {
      // 15,000 in 15 of 30 days projects to 30,000 against a 40,000 cap.
      final found = insights(
        now: now,
        thisMonth: [spend('Food', 1500000, DateTime(2026, 6, 5))],
        cap: 4000000,
      );
      expect(found.first.kind, InsightKind.budget);
      expect(found.first.tone, InsightTone.good);
      expect(found.first.text, contains('₹10000 under budget'));
    });

    test('warns when the pace would break the budget', () {
      final found = insights(
        now: now,
        thisMonth: [spend('Food', 1500000, DateTime(2026, 6, 5))],
        cap: 2000000,
      );
      expect(found.first.tone, InsightTone.warn);
      expect(found.first.text, contains('₹10000 over budget'));
    });

    test('says so when the budget is already broken', () {
      final found = insights(
        now: now,
        thisMonth: [spend('Food', 2500000, DateTime(2026, 6, 5))],
        cap: 2000000,
      );
      expect(found.first.text, 'You are ₹5000 over this month\'s budget.');
    });

    test('a finished month reports how it ended', () {
      final found = insights(
        now: now,
        month: 5,
        thisMonth: [spend('Food', 1500000, DateTime(2026, 5, 20))],
        cap: 2000000,
      );
      expect(found.first.text, 'Finished ₹5000 under budget.');
    });

    test('names the category that moved most, like for like', () {
      final found = insights(
        now: now,
        thisMonth: [
          spend('Food', 600000, DateTime(2026, 6, 4)),
          spend('Fuel', 200000, DateTime(2026, 6, 6)),
        ],
        lastMonth: [
          spend('Food', 400000, DateTime(2026, 5, 4)),
          spend('Fuel', 190000, DateTime(2026, 5, 6)),
          // After the 15th: not part of "by this day last month".
          spend('Food', 900000, DateTime(2026, 5, 25)),
        ],
      );
      final category = found.firstWhere((i) => i.kind == InsightKind.category);
      expect(category.tone, InsightTone.warn);
      expect(category.text,
          'Food is up 50% on by this day last month (₹2000 more).');
    });

    test('a past month compares whole months', () {
      final found = insights(
        now: now,
        month: 5,
        thisMonth: [spend('Food', 300000, DateTime(2026, 5, 25))],
        lastMonth: [spend('Food', 600000, DateTime(2026, 4, 28))],
      );
      final category = found.firstWhere((i) => i.kind == InsightKind.category);
      expect(category.tone, InsightTone.good);
      expect(
          category.text, 'Food is down 50% on the month before (₹3000 less).');
      final total = found.firstWhere((i) => i.kind == InsightKind.total);
      expect(total.text, 'Spending is 50% lower than the month before.');
    });

    test('a small category doubling is not news', () {
      final found = insights(
        now: now,
        thisMonth: [
          spend('Rent', 2000000, DateTime(2026, 6, 1)),
          spend('Snacks', 8000, DateTime(2026, 6, 2)),
        ],
        lastMonth: [
          spend('Rent', 2000000, DateTime(2026, 5, 1)),
          spend('Snacks', 4000, DateTime(2026, 5, 2)),
        ],
      );
      expect(found.where((i) => i.kind == InsightKind.category), isEmpty);
    });

    test('a refund comes off its category', () {
      final found = insights(
        now: now,
        thisMonth: [
          spend('Shopping', 500000, DateTime(2026, 6, 2)),
          spend('Shopping', -300000, DateTime(2026, 6, 3)),
        ],
        lastMonth: [spend('Shopping', 400000, DateTime(2026, 5, 2))],
      );
      final category = found.firstWhere((i) => i.kind == InsightKind.category);
      expect(category.text, startsWith('Shopping is down 50%'));
    });

    test('reports the share of income kept', () {
      final found = insights(
        now: now,
        thisMonth: [spend('Rent', 3000000, DateTime(2026, 6, 1))],
        income: 5000000,
      );
      final savings = found.firstWhere((i) => i.kind == InsightKind.savings);
      expect(savings.tone, InsightTone.good);
      expect(savings.text, 'You\'ve kept 40% of this month\'s income so far.');
    });

    test('names the biggest expense by its description', () {
      final found = insights(
        now: now,
        thisMonth: [
          spend('Rent', 3000000, DateTime(2026, 6, 1),
              description: 'House rent'),
          spend('Food', 50000, DateTime(2026, 6, 2)),
        ],
      );
      expect(found.last.text, 'Biggest expense: ₹30000 on House rent.');
    });

    test('income rows are not spending', () {
      final found = insights(
        now: now,
        thisMonth: [
          Expense(
              description: 'Salary',
              amount: 9000000,
              date: DateTime(2026, 6, 1),
              category: 'Salary',
              paymentMode: 'Bank',
              type: DbConstants.txIncome),
        ],
      );
      expect(found, isEmpty);
    });

    test('keeps to the limit, most useful first', () {
      final found = insights(
        now: now,
        thisMonth: [
          spend('Food', 600000, DateTime(2026, 6, 4)),
          spend('Fuel', 200000, DateTime(2026, 6, 6)),
        ],
        lastMonth: [spend('Food', 300000, DateTime(2026, 5, 4))],
        income: 5000000,
        cap: 4000000,
        limit: 3,
      );
      expect(found.map((i) => i.kind), [
        InsightKind.budget,
        InsightKind.category,
        InsightKind.total,
      ]);
    });

    test('a month that has not started says nothing', () {
      expect(
          insights(
            now: now,
            month: 7,
            thisMonth: [spend('Rent', 100, DateTime(2026, 7, 1))],
          ),
          isEmpty);
    });
  });

  group('noSpendStreak', () {
    test('counts whole days since the last purchase, up to yesterday', () {
      // Spent on the 11th; the 12th, 13th and 14th are clear; today is open.
      expect(
          noSpendStreak([spend('Food', 100, DateTime(2026, 6, 11, 21))], now),
          3);
    });

    test('spending today or yesterday means no streak', () {
      expect(noSpendStreak([spend('Food', 100, DateTime(2026, 6, 15, 8))], now),
          0);
      expect(
          noSpendStreak([spend('Food', 100, DateTime(2026, 6, 14, 23))], now),
          0);
    });

    test('no purchases at all is not a streak', () {
      expect(noSpendStreak(const [], now), 0);
    });

    test('refunds and income do not break it; future rows are ignored', () {
      final rows = [
        spend('Food', 100, DateTime(2026, 6, 10)),
        spend('Food', -100, DateTime(2026, 6, 13)),
        Expense(
            description: 'Salary',
            amount: 100,
            date: DateTime(2026, 6, 14),
            category: 'Salary',
            paymentMode: 'Bank',
            type: DbConstants.txIncome),
        spend('Rent', 100, DateTime(2026, 6, 20)),
      ];
      expect(noSpendStreak(rows, now), 4);
    });

    test('runs across a month boundary', () {
      expect(
          noSpendStreak([spend('Food', 100, DateTime(2026, 5, 29))],
              DateTime(2026, 6, 2)),
          3);
    });
  });
}
