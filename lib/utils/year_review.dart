import '../models/expense.dart';

/// One calendar year's income and spending, month by month, with the
/// headline figures a year-in-review shows. Pure, so it can be unit-tested.
class YearReview {
  final int year;

  /// Spending and income per month, January first, in base-currency minor
  /// units. Refunds (negative expenses) come off the month they landed in.
  final List<int> monthlyExpense;
  final List<int> monthlyIncome;

  /// Months of the year that have happened by "now": 12 for a past year, the
  /// current month's number for this year, 0 for a year still to come.
  final int monthsElapsed;

  /// The largest single expense of the year, or null when there were none.
  final Expense? biggest;

  /// Days of the year, up to "now", on which nothing was spent.
  final int noSpendDays;

  const YearReview({
    required this.year,
    required this.monthlyExpense,
    required this.monthlyIncome,
    required this.monthsElapsed,
    required this.biggest,
    required this.noSpendDays,
  });

  /// Builds the review from [rows] (any year's rows may be passed; only
  /// [year]'s are counted). [baseAmountOf] converts a row to base currency.
  factory YearReview.from(
    Iterable<Expense> rows, {
    required int year,
    required int Function(Expense) baseAmountOf,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final expense = List<int>.filled(12, 0);
    final income = List<int>.filled(12, 0);
    final spendDays = <int>{};
    Expense? biggest;
    var biggestAmount = 0;
    for (final e in rows) {
      if (e.date.year != year) continue;
      final amount = baseAmountOf(e);
      if (e.isIncome) {
        income[e.date.month - 1] += amount;
      } else if (e.isExpense) {
        expense[e.date.month - 1] += amount;
        if (amount > 0) {
          spendDays.add(e.date.month * 100 + e.date.day);
          if (amount > biggestAmount) {
            biggestAmount = amount;
            biggest = e;
          }
        }
      }
    }
    final elapsed = year < today.year
        ? 12
        : year == today.year
            ? today.month
            : 0;
    // Days of the year that have happened, through today.
    final lastDay = year < today.year
        ? DateTime(year, 12, 31)
        : DateTime(today.year, today.month, today.day);
    final daysSoFar = year > today.year
        ? 0
        : DateTime.utc(lastDay.year, lastDay.month, lastDay.day)
                .difference(DateTime.utc(year))
                .inDays +
            1;
    final spentOn = spendDays.where((d) {
      final date = DateTime(year, d ~/ 100, d % 100);
      return !date.isAfter(lastDay);
    }).length;
    return YearReview(
      year: year,
      monthlyExpense: expense,
      monthlyIncome: income,
      monthsElapsed: elapsed,
      biggest: biggest,
      noSpendDays: daysSoFar - spentOn < 0 ? 0 : daysSoFar - spentOn,
    );
  }

  int get totalExpense => monthlyExpense.fold(0, (s, v) => s + v);
  int get totalIncome => monthlyIncome.fold(0, (s, v) => s + v);

  bool get isEmpty =>
      monthlyExpense.every((v) => v == 0) && monthlyIncome.every((v) => v == 0);

  /// Average spending per month that has happened, or 0 when none has.
  int get averageMonthlyExpense =>
      monthsElapsed == 0 ? 0 : (totalExpense / monthsElapsed).round();

  /// Month (1–12) with the most spending, or null when nothing was spent.
  int? get highestMonth {
    int? best;
    for (var m = 0; m < 12; m++) {
      if (monthlyExpense[m] <= 0) continue;
      if (best == null || monthlyExpense[m] > monthlyExpense[best]) best = m;
    }
    return best == null ? null : best + 1;
  }

  /// Month (1–12) with the least spending among those that have happened and
  /// had any, or null when fewer than two months had spending (the lowest
  /// would just repeat the highest).
  int? get lowestMonth {
    int? best;
    var withSpend = 0;
    for (var m = 0; m < monthsElapsed && m < 12; m++) {
      if (monthlyExpense[m] <= 0) continue;
      withSpend++;
      if (best == null || monthlyExpense[m] < monthlyExpense[best]) best = m;
    }
    return withSpend < 2 || best == null ? null : best + 1;
  }

  /// Month (1–12) in which the most was kept (income less spending), or null
  /// when no month had income.
  int? get bestSavingMonth {
    int? best;
    for (var m = 0; m < 12; m++) {
      if (monthlyIncome[m] <= 0) continue;
      final saved = monthlyIncome[m] - monthlyExpense[m];
      if (best == null || saved > monthlyIncome[best] - monthlyExpense[best]) {
        best = m;
      }
    }
    return best == null ? null : best + 1;
  }
}
