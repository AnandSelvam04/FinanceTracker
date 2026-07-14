import '../models/budget.dart';
import '../models/recurring_rule.dart';

/// Pure alert-computation logic, kept free of Flutter/DB dependencies so it
/// can be unit-tested and reused by any surface (dashboard banner today,
/// OS notifications later).

class BudgetAlert {
  final String category;

  /// Amount spent and the budget cap, both in minor units.
  final int spent;
  final int budget;

  const BudgetAlert({
    required this.category,
    required this.spent,
    required this.budget,
  });

  double get ratio => budget <= 0 ? 0 : spent / budget;
  bool get isOver => spent > budget;
}

class BillAlert {
  final String description;

  /// Amount in minor units.
  final int amount;
  final DateTime dueDate;

  /// Whole days until due; negative means overdue.
  final int daysUntil;

  const BillAlert({
    required this.description,
    required this.amount,
    required this.dueDate,
    required this.daysUntil,
  });

  bool get isOverdue => daysUntil < 0;
  bool get isToday => daysUntil == 0;
}

/// Budgets for [year]/[month] whose spend has reached [warnAt] of the cap,
/// most-strained first. [spentForCategory] returns minor-unit spend for a
/// category in that month.
List<BudgetAlert> budgetAlerts({
  required List<Budget> budgets,
  required int year,
  required int month,
  required int Function(String category) spentForCategory,
  double warnAt = 0.9,
}) {
  final alerts = <BudgetAlert>[];
  for (final b in budgets) {
    if (b.year != year || b.month != month || b.amount <= 0) continue;
    final spent = spentForCategory(b.category);
    if (spent / b.amount >= warnAt) {
      alerts.add(
          BudgetAlert(category: b.category, spent: spent, budget: b.amount));
    }
  }
  alerts.sort((a, b) => b.ratio.compareTo(a.ratio));
  return alerts;
}

/// Enabled recurring rules due within the next [withinDays] days (or already
/// overdue), soonest first.
List<BillAlert> upcomingBills({
  required List<RecurringRule> rules,
  required DateTime now,
  int withinDays = 3,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final alerts = <BillAlert>[];
  for (final r in rules) {
    if (!r.enabled) continue;
    final due = DateTime(r.nextDue.year, r.nextDue.month, r.nextDue.day);
    final days = due.difference(today).inDays;
    if (days <= withinDays) {
      alerts.add(BillAlert(
        description: r.description,
        amount: r.amount,
        dueDate: r.nextDue,
        daysUntil: days,
      ));
    }
  }
  alerts.sort((a, b) => a.daysUntil.compareTo(b.daysUntil));
  return alerts;
}
