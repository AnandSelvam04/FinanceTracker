import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/budget.dart';
import 'package:finance_tracker/models/recurring_rule.dart';
import 'package:finance_tracker/utils/alerts.dart';
import 'package:finance_tracker/utils/db_constants.dart';

void main() {
  group('budgetAlerts', () {
    final budgets = [
      Budget(category: 'Food', amount: 10000, year: 2026, month: 7),
      Budget(category: 'Rent', amount: 20000, year: 2026, month: 7),
      Budget(category: 'Fun', amount: 5000, year: 2026, month: 7),
      Budget(category: 'Old', amount: 5000, year: 2026, month: 6),
    ];

    int spent(String c) => {
          'Food': 9500, // 95% -> warn
          'Rent': 25000, // 125% -> over
          'Fun': 1000, // 20% -> below threshold
          'Old': 9000, // wrong month
        }[c]!;

    test('flags budgets at/over the warn threshold for the given month', () {
      final alerts = budgetAlerts(
        budgets: budgets,
        year: 2026,
        month: 7,
        spentForCategory: spent,
      );
      // Rent (over) first, then Food (warn); Fun below, Old wrong month.
      expect(alerts.map((a) => a.category).toList(), ['Rent', 'Food']);
      expect(alerts.first.isOver, isTrue);
      expect(alerts.last.isOver, isFalse);
    });

    test('ignores budgets with a zero cap', () {
      final alerts = budgetAlerts(
        budgets: [Budget(category: 'X', amount: 0, year: 2026, month: 7)],
        year: 2026,
        month: 7,
        spentForCategory: (_) => 100,
      );
      expect(alerts, isEmpty);
    });
  });

  group('upcomingBills', () {
    RecurringRule rule(String desc, DateTime due, {bool enabled = true}) =>
        RecurringRule(
          description: desc,
          amount: 1000,
          category: 'Bills',
          frequency: DbConstants.freqMonthly,
          nextDue: due,
          enabled: enabled,
        );

    test('includes due-soon and overdue enabled rules, soonest first', () {
      final now = DateTime(2026, 7, 14);
      final alerts = upcomingBills(
        rules: [
          rule('Rent', DateTime(2026, 7, 16)), // in 2 days
          rule('Netflix', DateTime(2026, 7, 20)), // beyond window
          rule('Phone', DateTime(2026, 7, 13)), // overdue by 1
          rule('Gym', DateTime(2026, 7, 14)), // today
          rule('Paused', DateTime(2026, 7, 15), enabled: false),
        ],
        now: now,
      );
      expect(alerts.map((a) => a.description).toList(),
          ['Phone', 'Gym', 'Rent']);
      expect(alerts.first.isOverdue, isTrue);
      expect(alerts[1].isToday, isTrue);
    });
  });
}
