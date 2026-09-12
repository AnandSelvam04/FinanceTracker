import '../models/account.dart';
import 'alerts.dart' show calendarDaysBetween;

/// Credit-card billing-cycle maths, kept free of Flutter/DB dependencies so it
/// can be unit-tested and reused by the dashboard banner and the notification
/// scheduler alike.
///
/// A card's statement is generated on [Account.statementDay] each month and
/// covers the cycle that just closed; payment is due on [Account.dueDay].

/// The windows and dates derived from a card's statement/due days for a given
/// reference date. All dates are date-only (local midnight).
class CreditCardCycle {
  /// Start of the cycle that the most recent statement bills (inclusive).
  final DateTime billedCycleStart;

  /// The most recent statement date (also the end, exclusive, of the billed
  /// cycle and the start of the current open cycle).
  final DateTime statementDate;

  /// End (exclusive) of the current open cycle — the next statement date.
  final DateTime nextStatementDate;

  /// When payment for the most recent statement is due.
  final DateTime dueDate;

  /// Whole days from the reference date to [dueDate]; negative means overdue.
  final int daysUntilDue;

  const CreditCardCycle({
    required this.billedCycleStart,
    required this.statementDate,
    required this.nextStatementDate,
    required this.dueDate,
    required this.daysUntilDue,
  });
}

/// A date on the given month with [day] clamped to that month's length, so a
/// statement day of 31 lands on the 28th–30th in shorter months rather than
/// spilling into the next one. [month] may be 0/13 etc.; it is normalized.
DateTime _dateWithDay(int year, int month, int day) {
  final firstOfMonth = DateTime(year, month, 1);
  final lastDay = DateTime(firstOfMonth.year, firstOfMonth.month + 1, 0).day;
  final d = day < 1 ? 1 : (day > lastDay ? lastDay : day);
  return DateTime(firstOfMonth.year, firstOfMonth.month, d);
}

/// Computes the billing cycle for [statementDay]/[dueDay] relative to [now].
CreditCardCycle computeCreditCardCycle({
  required int statementDay,
  required int dueDay,
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);

  // The most recent statement date on or before today.
  final stmtThisMonth = _dateWithDay(today.year, today.month, statementDay);
  final statementDate = today.isBefore(stmtThisMonth)
      ? _dateWithDay(today.year, today.month - 1, statementDay)
      : stmtThisMonth;

  final billedCycleStart =
      _dateWithDay(statementDate.year, statementDate.month - 1, statementDay);
  final nextStatementDate =
      _dateWithDay(statementDate.year, statementDate.month + 1, statementDay);

  // Payment is due on the first occurrence of the due day on or after the
  // statement date (same month when dueDay >= statementDay, otherwise next).
  var dueDate = _dateWithDay(statementDate.year, statementDate.month, dueDay);
  if (dueDate.isBefore(statementDate)) {
    dueDate =
        _dateWithDay(statementDate.year, statementDate.month + 1, dueDay);
  }

  return CreditCardCycle(
    billedCycleStart: billedCycleStart,
    statementDate: statementDate,
    nextStatementDate: nextStatementDate,
    dueDate: dueDate,
    daysUntilDue: calendarDaysBetween(today, dueDate),
  );
}

/// A due-payment reminder for one credit card.
class CreditCardReminder {
  final int accountId;
  final String accountName;

  /// The card's display currency symbol.
  final String symbol;

  /// Amount billed on the most recent statement, in the card's own currency
  /// (minor units).
  final int statementAmount;

  /// Amount spent so far in the current (open) cycle, in the card's currency.
  final int currentCycleSpend;

  final DateTime dueDate;

  /// Whole days until [dueDate]; negative means overdue.
  final int daysUntilDue;

  const CreditCardReminder({
    required this.accountId,
    required this.accountName,
    required this.symbol,
    required this.statementAmount,
    required this.currentCycleSpend,
    required this.dueDate,
    required this.daysUntilDue,
  });

  bool get isOverdue => daysUntilDue < 0;
  bool get isToday => daysUntilDue == 0;
}

/// Builds payment reminders for every credit card that has a billing cycle set
/// and a non-empty statement, whose due date falls within [withinDays] ahead
/// (or is at most [overdueGrace] days overdue), soonest first.
///
/// [spendInRange] returns the card's own-currency spend on [accountId] over
/// `[start, endExclusive)`.
List<CreditCardReminder> creditCardReminders({
  required List<Account> accounts,
  required DateTime now,
  required int Function(int accountId, DateTime start, DateTime endExclusive)
      spendInRange,
  int withinDays = 7,
  int overdueGrace = 7,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));
  final out = <CreditCardReminder>[];
  for (final a in accounts) {
    if (!a.hasBillingCycle || a.id == null) continue;
    final cycle = computeCreditCardCycle(
      statementDay: a.statementDay!,
      dueDay: a.dueDay!,
      now: now,
    );
    final statementAmount =
        spendInRange(a.id!, cycle.billedCycleStart, cycle.statementDate);
    // Nothing billed means nothing to pay — no reminder.
    if (statementAmount <= 0) continue;
    if (cycle.daysUntilDue > withinDays || cycle.daysUntilDue < -overdueGrace) {
      continue;
    }
    final cycleSpend = spendInRange(a.id!, cycle.statementDate, tomorrow);
    out.add(CreditCardReminder(
      accountId: a.id!,
      accountName: a.name,
      symbol: a.symbol,
      statementAmount: statementAmount,
      currentCycleSpend: cycleSpend,
      dueDate: cycle.dueDate,
      daysUntilDue: cycle.daysUntilDue,
    ));
  }
  out.sort((x, y) => x.daysUntilDue.compareTo(y.daysUntilDue));
  return out;
}
