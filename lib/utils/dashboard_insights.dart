import '../models/expense.dart';
import 'alerts.dart';

/// How an insight should be read at a glance.
enum InsightTone { good, warn, neutral }

/// What an insight is about, for its icon.
enum InsightKind { budget, category, total, savings, biggest }

/// One plain-language observation about a month's spending.
class Insight {
  final InsightKind kind;
  final InsightTone tone;
  final String text;
  const Insight(this.kind, this.tone, this.text);

  @override
  String toString() => 'Insight($kind, $tone, $text)';
}

/// Up to [limit] things worth saying about [month] of [year], most useful
/// first: where the budget is heading, the category that moved most, how
/// total spending compares, how much of the income was kept, and the biggest
/// single expense.
///
/// Comparisons are like for like. For the month in progress, last month is
/// counted only up to the same day — on the 10th, ten days of this month
/// against a whole previous month would make every category look "down".
///
/// [thisMonth] and [lastMonth] are the expense rows of the month and of the
/// one before it; amounts go through [baseAmountOf] (refunds are negative
/// and come off). [money] formats a figure for the sentence.
List<Insight> dashboardInsights({
  required int year,
  required int month,
  required DateTime now,
  required List<Expense> thisMonth,
  required List<Expense> lastMonth,
  required int Function(Expense) baseAmountOf,
  required int income,
  required int overallCap,
  required String Function(int minor) money,
  int limit = 3,
}) {
  final isCurrent = now.year == year && now.month == month;
  // Nothing useful can be said about a month that has not started.
  if (DateTime(year, month).isAfter(now)) return const [];
  final throughDay = isCurrent ? now.day : 31;
  final versus = isCurrent ? 'by this day last month' : 'the month before';

  int sum(Iterable<Expense> rows) =>
      rows.fold<int>(0, (t, e) => t + baseAmountOf(e));
  Map<String, int> byCategory(Iterable<Expense> rows) {
    final totals = <String, int>{};
    for (final e in rows) {
      totals[e.category] = (totals[e.category] ?? 0) + baseAmountOf(e);
    }
    return totals;
  }

  final current = thisMonth.where((e) => e.isExpense).toList();
  final previous =
      lastMonth.where((e) => e.isExpense && e.date.day <= throughDay).toList();
  final spent = sum(current);
  final spentBefore = sum(previous);
  if (current.isEmpty) return const [];

  final insights = <Insight>[];

  // 1. Where the overall budget is heading (or where it ended up).
  if (overallCap > 0) {
    if (isCurrent) {
      final pace = budgetPace(
          spent: spent, cap: overallCap, year: year, month: month, now: now);
      if (spent > overallCap) {
        insights.add(Insight(InsightKind.budget, InsightTone.warn,
            'You are ${money(spent - overallCap)} over this month\'s budget.'));
      } else if (pace != null && pace.projected > overallCap) {
        insights.add(Insight(
            InsightKind.budget,
            InsightTone.warn,
            'At this pace you\'ll end the month '
            '${money(pace.projected - overallCap)} over budget.'));
      } else if (pace != null) {
        insights.add(Insight(
            InsightKind.budget,
            InsightTone.good,
            'At this pace you\'ll end the month '
            '${money(overallCap - pace.projected)} under budget.'));
      }
    } else {
      insights.add(spent > overallCap
          ? Insight(InsightKind.budget, InsightTone.warn,
              'Finished ${money(spent - overallCap)} over budget.')
          : Insight(InsightKind.budget, InsightTone.good,
              'Finished ${money(overallCap - spent)} under budget.'));
    }
  }

  // 2. The category that moved most against last month. Small categories
  // are ignored: 40 → 80 is "up 100%" and tells nobody anything.
  final nowBy = byCategory(current);
  final beforeBy = byCategory(previous);
  final floor = (spent * 0.05).round();
  String? mover;
  var moverDiff = 0;
  for (final category in {...nowBy.keys, ...beforeBy.keys}) {
    final a = nowBy[category] ?? 0, b = beforeBy[category] ?? 0;
    final diff = a - b;
    if (diff.abs() < floor || diff.abs() <= moverDiff.abs()) continue;
    // Needs a base to compare against, and a change of a tenth or more.
    if (b <= 0 || diff.abs() * 10 < b) continue;
    mover = category;
    moverDiff = diff;
  }
  if (mover != null) {
    final before = beforeBy[mover]!;
    final percent = (moverDiff.abs() * 100 / before).round();
    insights.add(Insight(
        InsightKind.category,
        moverDiff > 0 ? InsightTone.warn : InsightTone.good,
        '$mover is ${moverDiff > 0 ? 'up' : 'down'} $percent% on $versus '
        '(${money(moverDiff.abs())} ${moverDiff > 0 ? 'more' : 'less'}).'));
  } else {
    // No mover, but a sizeable category with no spending before it is news.
    String? fresh;
    for (final entry in nowBy.entries) {
      if ((beforeBy[entry.key] ?? 0) > 0 || spentBefore <= 0) continue;
      if (entry.value * 5 < spent) continue;
      if (fresh == null || entry.value > nowBy[fresh]!) fresh = entry.key;
    }
    if (fresh != null) {
      insights.add(Insight(InsightKind.category, InsightTone.neutral,
          '$fresh is new this month: ${money(nowBy[fresh]!)} so far.'));
    }
  }

  // 3. Total spending against last month.
  if (spentBefore > 0 && spent > 0) {
    final diff = spent - spentBefore;
    final percent = (diff.abs() * 100 / spentBefore).round();
    if (percent >= 5) {
      insights.add(Insight(
          InsightKind.total,
          diff > 0 ? InsightTone.warn : InsightTone.good,
          'Spending is $percent% ${diff > 0 ? 'higher' : 'lower'} than '
          '$versus.'));
    }
  }

  // 4. How much of the income was kept.
  if (income > 0 && spent >= 0 && spent < income) {
    final kept = ((income - spent) * 100 / income).round();
    if (kept >= 1) {
      insights.add(Insight(
          InsightKind.savings,
          kept >= 20 ? InsightTone.good : InsightTone.neutral,
          isCurrent
              ? 'You\'ve kept $kept% of this month\'s income so far.'
              : 'You kept $kept% of the month\'s income.'));
    }
  }

  // 5. The biggest single expense.
  Expense? biggest;
  for (final e in current) {
    if (biggest == null || baseAmountOf(e) > baseAmountOf(biggest)) biggest = e;
  }
  if (biggest != null && baseAmountOf(biggest) > 0 && current.length > 1) {
    final what = biggest.description.trim().isEmpty
        ? biggest.category
        : biggest.description.trim();
    insights.add(Insight(InsightKind.biggest, InsightTone.neutral,
        'Biggest expense: ${money(baseAmountOf(biggest))} on $what.'));
  }

  return insights.take(limit).toList();
}

/// Whole days in a row, up to and including yesterday, on which nothing was
/// spent — today is left out because it is not over. Zero when something
/// was spent today or yesterday, and when [rows] hold no spending at all
/// (there is no last spending day to count from).
///
/// Only purchases count: a refund or income on a day does not break it.
int noSpendStreak(Iterable<Expense> rows, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  DateTime? last;
  for (final e in rows) {
    if (!e.isExpense || e.amount <= 0) continue;
    final day = DateTime(e.date.year, e.date.month, e.date.day);
    if (day.isAfter(today)) continue;
    if (last == null || day.isAfter(last)) last = day;
  }
  if (last == null) return 0;
  // Calendar days, not 24-hour spans, so a daylight-saving change can't
  // shorten the count.
  final gap = DateTime.utc(today.year, today.month, today.day)
      .difference(DateTime.utc(last.year, last.month, last.day))
      .inDays;
  return gap <= 1 ? 0 : gap - 1;
}
