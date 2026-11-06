import '../models/budget.dart';
import 'category_suggestions.dart';

/// How far back a rollover chain looks. Keeps the carry bounded and within
/// the years a screen already loads (the month on screen and the one before).
const int kMaxRolloverMonths = 12;

/// What [budget] inherits from earlier months when rollover is on: the
/// unspent part of each previous month's cap for the same category (or
/// overall cap), less any overspend, accumulated month by month.
///
/// The chain runs back through consecutive months that have a cap for the
/// category and stops at the first month without one, so deleting a cap for
/// a month resets the carry. Positive means extra room this month; negative
/// means last month's overspend comes off this month's cap.
///
/// [spentIn] returns base-currency minor-unit spend for the budget's category
/// in a month (for the overall cap, the month's total spend).
int budgetCarry({
  required Budget budget,
  required List<Budget> budgets,
  required int Function(int year, int month) spentIn,
  int maxMonths = kMaxRolloverMonths,
}) {
  final key = budget.isOverall ? null : normalizeCategory(budget.category);
  Budget? capFor(int year, int month) {
    for (final b in budgets) {
      if (b.year != year || b.month != month) continue;
      if (budget.isOverall
          ? b.isOverall
          : (!b.isOverall && normalizeCategory(b.category) == key)) {
        return b;
      }
    }
    return null;
  }

  // Walk back to the start of the chain, then fold forward so an overspend
  // in one month is absorbed by what had been carried into it.
  final chain = <(Budget, int, int)>[];
  for (var i = 1; i <= maxMonths; i++) {
    final d = DateTime(budget.year, budget.month - i);
    final cap = capFor(d.year, d.month);
    if (cap == null) break;
    chain.add((cap, d.year, d.month));
  }
  var carry = 0;
  for (final (cap, year, month) in chain.reversed) {
    carry += cap.amount - spentIn(year, month);
  }
  return carry;
}

/// [budget]'s cap with its rollover carry applied, never below zero.
int effectiveCap(Budget budget, int carry) {
  final cap = budget.amount + carry;
  return cap < 0 ? 0 : cap;
}
