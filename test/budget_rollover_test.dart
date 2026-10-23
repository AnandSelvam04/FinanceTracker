import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/budget.dart';
import 'package:finance_tracker/utils/alerts.dart';
import 'package:finance_tracker/utils/budget_rollover.dart';

void main() {
  Budget cap(String category, int amount, int year, int month) =>
      Budget(category: category, amount: amount, year: year, month: month);

  // Spend per (year, month); anything missing is zero.
  int Function(int, int) spending(Map<(int, int), int> spend) =>
      (y, m) => spend[(y, m)] ?? 0;

  test('unspent budget carries into the next month', () {
    final budgets = [cap('Food', 10000, 2026, 5), cap('Food', 10000, 2026, 6)];
    final carry = budgetCarry(
        budget: budgets[1],
        budgets: budgets,
        spentIn: spending({(2026, 5): 7000}));
    expect(carry, 3000);
    expect(effectiveCap(budgets[1], carry), 13000);
  });

  test('carry accumulates and overspend is absorbed month by month', () {
    final budgets = [
      cap('Food', 10000, 2026, 3),
      cap('food ', 10000, 2026, 4), // matched case-insensitively
      cap('Food', 10000, 2026, 5),
      cap('Food', 10000, 2026, 6),
    ];
    final carry = budgetCarry(
        budget: budgets[3],
        budgets: budgets,
        spentIn:
            spending({(2026, 3): 6000, (2026, 4): 5000, (2026, 5): 12000}));
    // +4000, +5000, -2000.
    expect(carry, 7000);
  });

  test('overspend reduces the cap but never below zero', () {
    final budgets = [cap('Fun', 5000, 2026, 5), cap('Fun', 5000, 2026, 6)];
    final carry = budgetCarry(
        budget: budgets[1],
        budgets: budgets,
        spentIn: spending({(2026, 5): 12000}));
    expect(carry, -7000);
    expect(effectiveCap(budgets[1], carry), 0);
  });

  test('a month without a cap breaks the chain', () {
    final budgets = [
      cap('Food', 10000, 2026, 3),
      // No April cap.
      cap('Food', 10000, 2026, 5),
      cap('Food', 10000, 2026, 6),
    ];
    final carry = budgetCarry(
        budget: budgets[2], budgets: budgets, spentIn: spending({}));
    expect(carry, 10000); // May only
  });

  test('crosses the year boundary; overall cap chains on its own', () {
    final budgets = [
      cap(Budget.overallCategory, 50000, 2025, 12),
      cap('Food', 99999, 2025, 12),
      cap(Budget.overallCategory, 50000, 2026, 1),
    ];
    final carry = budgetCarry(
        budget: budgets[2],
        budgets: budgets,
        spentIn: spending({(2025, 12): 40000}));
    expect(carry, 10000);
  });

  test('alerts measure against the cap with rollover', () {
    final budgets = [cap('Food', 10000, 2026, 6), cap('Fun', 5000, 2026, 6)];
    final alerts = budgetAlerts(
      budgets: budgets,
      year: 2026,
      month: 6,
      spentForCategory: (c) => c == 'Food' ? 9500 : 100,
      // Food carried in 5000; Fun's earlier overspend used up its cap.
      capFor: (b) => b.category == 'Food' ? 15000 : 0,
    );
    expect(alerts.map((a) => a.category), ['Fun']);
    expect(alerts.single.isOver, isTrue);
  });
}
