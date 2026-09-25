import '../utils/db_constants.dart';

/// Something the user is saving toward — an emergency fund, a trip, a phone —
/// with a target amount, what has been set aside so far, and an optional date
/// to reach it by.
///
/// Deliberately separate from accounts: money "in" a goal is earmarked, not
/// moved, so contributing to a goal never changes an account balance or the
/// net-worth total.
class SavingsGoal {
  final int? id;
  final String name;

  /// Target and amount saved so far, both in base-currency minor units.
  final int target;
  final int saved;

  /// Date the user wants to reach the target by; null = no deadline.
  final DateTime? targetDate;

  /// ARGB color for the goal's ring; null = derive from the theme.
  final int? color;

  const SavingsGoal({
    this.id,
    required this.name,
    required this.target,
    this.saved = 0,
    this.targetDate,
    this.color,
  });

  int get remaining => saved >= target ? 0 : target - saved;
  bool get isComplete => target > 0 && saved >= target;

  /// Share of the target saved, clamped to 0..1 for progress indicators.
  double get progress =>
      target <= 0 ? 0 : (saved / target).clamp(0.0, 1.0).toDouble();

  /// Whole calendar months from [now] until [targetDate], counting the current
  /// month as one when the date is still ahead, so a goal due later this month
  /// asks for the full remainder now. Null without a deadline; 0 once passed.
  int? monthsLeft(DateTime now) {
    final due = targetDate;
    if (due == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(due.year, due.month, due.day);
    if (dueDay.isBefore(today)) return 0;
    return (due.year - now.year) * 12 + due.month - now.month + 1;
  }

  /// What has to be set aside each month to reach the target on time, in
  /// minor units (rounded up so the last month is never short). Null without
  /// a deadline or once complete; the whole remainder when the date has
  /// passed.
  int? monthlyNeeded(DateTime now) {
    if (isComplete) return null;
    final months = monthsLeft(now);
    if (months == null) return null;
    if (months <= 0) return remaining;
    return (remaining + months - 1) ~/ months;
  }

  /// Whether the deadline has passed with the target still unmet.
  bool isOverdue(DateTime now) => !isComplete && monthsLeft(now) == 0;

  SavingsGoal copyWith({
    int? id,
    String? name,
    int? target,
    int? saved,
    DateTime? targetDate,
    bool clearTargetDate = false,
    int? color,
  }) =>
      SavingsGoal(
        id: id ?? this.id,
        name: name ?? this.name,
        target: target ?? this.target,
        saved: saved ?? this.saved,
        targetDate: clearTargetDate ? null : (targetDate ?? this.targetDate),
        color: color ?? this.color,
      );

  Map<String, dynamic> toMap() => {
        DbConstants.colId: id,
        DbConstants.colName: name,
        DbConstants.colAmount: target,
        DbConstants.colSaved: saved,
        DbConstants.colDate: targetDate?.toIso8601String(),
        DbConstants.colColor: color,
      };

  factory SavingsGoal.fromMap(Map<String, dynamic> map) {
    final date = map[DbConstants.colDate];
    return SavingsGoal(
      id: map[DbConstants.colId],
      name: map[DbConstants.colName] ?? '',
      target: ((map[DbConstants.colAmount] ?? 0) as num).round(),
      saved: ((map[DbConstants.colSaved] ?? 0) as num).round(),
      targetDate:
          date is String && date.isNotEmpty ? DateTime.parse(date) : null,
      color: map[DbConstants.colColor],
    );
  }
}
