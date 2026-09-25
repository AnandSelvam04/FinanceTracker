import '../models/budget.dart';
import '../models/recurring_rule.dart';

/// Pure alert-computation logic, kept free of Flutter/DB dependencies so it
/// can be unit-tested and reused by any surface (dashboard banner today,
/// OS notifications later).

/// Share of a budget at which it counts as "nearly spent" — the point the
/// dashboard banner and the budget notifications fire at.
///
/// Defined once here and reused by the budgets screen's progress colours,
/// which previously hardcoded the same 0.9 and would have drifted from it.
const double kBudgetWarnRatio = 0.9;

/// Share of a budget at which the progress bar starts warning, ahead of
/// [kBudgetWarnRatio].
const double kBudgetCautionRatio = 0.7;

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
  double warnAt = kBudgetWarnRatio,
}) {
  final alerts = <BudgetAlert>[];
  for (final b in budgets) {
    // The overall monthly cap is surfaced on its own, not as a category alert.
    if (b.isOverall) continue;
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

/// Whole calendar days from [from] to [to], ignoring the time of day.
///
/// Computed in UTC on purpose: subtracting two local midnights spans 23 or 25
/// hours across a DST transition, and `inDays` truncates, so "due tomorrow"
/// rendered as "due today". UTC has no such days, so the count is exact.
int calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// Enabled recurring rules due within the next [withinDays] days (or already
/// overdue), soonest first.
List<BillAlert> upcomingBills({
  required List<RecurringRule> rules,
  required DateTime now,
  int withinDays = 3,
}) {
  final alerts = <BillAlert>[];
  for (final r in rules) {
    if (!r.enabled) continue;
    final days = calendarDaysBetween(now, r.nextDue);
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

/// Days of the month elapsed before a pace forecast is trusted. On day one or
/// two a single grocery run extrapolates to an absurd month-end figure, so the
/// forecast stays quiet until there is a little history to project from.
const int kMinPaceDays = 3;

/// A straight-line forecast of month-end spend against a budget cap.
class BudgetPace {
  /// Spend so far, the projected month-end spend, and the cap — minor units.
  final int spent;
  final int projected;
  final int cap;

  /// Days left in the month after today (0 on the last day).
  final int daysLeft;

  const BudgetPace({
    required this.spent,
    required this.projected,
    required this.cap,
    required this.daysLeft,
  });

  /// True when the current pace would finish the month above the cap, even
  /// though spend has not crossed it yet — the early warning the plain
  /// progress bar cannot give.
  bool get onTrackToOverspend => spent <= cap && projected > cap;

  /// What can still be spent per remaining day without breaking the cap
  /// (0 when the cap is already spent). On the last day, the whole remainder.
  int get dailyAllowance {
    final left = cap - spent;
    if (left <= 0) return 0;
    return daysLeft <= 0 ? left : left ~/ (daysLeft + 1);
  }
}

/// Number of days in [month] of [year].
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Forecasts month-end spend for a cap of [cap] in [year]/[month] as of [now],
/// by extrapolating the average daily spend so far.
///
/// Returns null when a forecast would mislead: the month is not the current
/// one (a past month's spend is final; a future month has none), the cap is
/// not positive, or fewer than [kMinPaceDays] days have elapsed.
BudgetPace? budgetPace({
  required int spent,
  required int cap,
  required int year,
  required int month,
  required DateTime now,
}) {
  if (cap <= 0 || now.year != year || now.month != month) return null;
  final elapsed = now.day;
  if (elapsed < kMinPaceDays) return null;
  final total = daysInMonth(year, month);
  final projected = (spent / elapsed * total).round();
  return BudgetPace(
    spent: spent,
    projected: projected < spent ? spent : projected,
    cap: cap,
    daysLeft: total - elapsed,
  );
}
