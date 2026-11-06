import '../models/account.dart';
import 'billing_cycle.dart';
import 'date_format.dart';

/// The spending window the Credit cards screen shows.
enum CardPeriodKind {
  /// Each card's own open cycle: since its last statement (this month for a
  /// card with no statement day set).
  cycle,
  thisMonth,
  lastMonth,

  /// A range the user picked.
  custom,
}

/// A resolved window, `[start, endExclusive)`, with a short label for it.
class CardRange {
  final DateTime start;
  final DateTime endExclusive;

  /// "Since 6 Nov", "Nov 2026", "1 Oct – 15 Oct".
  final String label;
  const CardRange(this.start, this.endExclusive, this.label);
}

/// The window [kind] means for [card] on [now]. [customStart] and
/// [customEnd] (both inclusive days) are used for [CardPeriodKind.custom].
CardRange cardRange(
  Account card,
  CardPeriodKind kind,
  DateTime now, {
  DateTime? customStart,
  DateTime? customEnd,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  final monthStart = DateTime(today.year, today.month, 1);
  switch (kind) {
    case CardPeriodKind.cycle:
      if (card.hasBillingCycle) {
        final cycle = computeCreditCardCycle(
            statementDay: card.statementDay!, dueDay: card.dueDay!, now: now);
        return CardRange(cycle.billedUntil, tomorrow,
            'Since ${formatCompactDate(cycle.billedUntil, now: now)}');
      }
      return CardRange(monthStart, tomorrow,
          'Since ${formatCompactDate(monthStart, now: now)}');
    case CardPeriodKind.thisMonth:
      return CardRange(
          monthStart, tomorrow, formatMonthYear(today.year, today.month));
    case CardPeriodKind.lastMonth:
      final last = DateTime(today.year, today.month - 1, 1);
      return CardRange(
          last, monthStart, formatMonthYear(last.year, last.month));
    case CardPeriodKind.custom:
      final s = customStart ?? monthStart;
      final e = customEnd ?? today;
      final start = DateTime(s.year, s.month, s.day);
      final end = DateTime(e.year, e.month, e.day + 1);
      return CardRange(
          start,
          end,
          '${formatCompactDate(start, now: now)} – '
          '${formatCompactDate(DateTime(e.year, e.month, e.day), now: now)}');
  }
}
