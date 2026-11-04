import '../models/expense.dart';

/// Net spending per day of the month in [rows] (day of month → base-currency
/// minor units). Only expenses count; a refund comes off its day. Days with
/// no spending are absent.
Map<int, int> dailySpend(
    Iterable<Expense> rows, int Function(Expense) baseAmountOf) {
  final totals = <int, int>{};
  for (final e in rows) {
    if (!e.isExpense) continue;
    totals[e.date.day] = (totals[e.date.day] ?? 0) + baseAmountOf(e);
  }
  return totals;
}

/// Heat level 0–4 for a day's [amount] against the month's biggest day
/// [max]: 0 for nothing spent (or a net refund), 4 for the biggest days.
int spendLevel(int amount, int max) {
  if (amount <= 0 || max <= 0) return 0;
  final share = amount / max;
  if (share > 0.75) return 4;
  if (share > 0.5) return 3;
  if (share > 0.25) return 2;
  return 1;
}
