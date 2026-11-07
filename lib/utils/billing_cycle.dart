import '../models/account.dart';
import 'alerts.dart' show calendarDaysBetween;

/// Credit-card billing-cycle maths, kept free of Flutter/DB dependencies so it
/// can be unit-tested and reused by the dashboard banner and the notification
/// scheduler alike.
///
/// A card's statement is generated on [Account.statementDay] each month and
/// covers the cycle that just closed — *including* the statement day itself,
/// the way Indian card issuers bill it (statement date 20: cycle 21 Jun – 20
/// Jul). Payment is due on [Account.dueDay].

/// The windows and dates derived from a card's statement/due days for a given
/// reference date. All dates are date-only (local midnight).
class CreditCardCycle {
  /// Start of the cycle that the most recent statement bills (inclusive):
  /// the day after the statement before it.
  final DateTime billedCycleStart;

  /// The most recent statement date, the last day the statement bills.
  final DateTime statementDate;

  /// The day after [statementDate]: the end (exclusive) of the billed cycle
  /// and the start of the current open cycle. A purchase on the statement day
  /// is on that statement, not the next one.
  DateTime get billedUntil =>
      DateTime(statementDate.year, statementDate.month, statementDate.day + 1);

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

  final previousStatement =
      _dateWithDay(statementDate.year, statementDate.month - 1, statementDay);
  final billedCycleStart = DateTime(previousStatement.year,
      previousStatement.month, previousStatement.day + 1);
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

/// When a purchase made on [day] gets billed and has to be paid: the
/// statement it lands on (the statement day itself counts towards that
/// day's statement) and that statement's due date, with the whole days of
/// interest-free credit in between.
({DateTime statement, DateTime due, int interestFreeDays}) purchaseWindow({
  required int statementDay,
  required int dueDay,
  required DateTime day,
}) {
  final today = DateTime(day.year, day.month, day.day);
  final now = computeCreditCardCycle(
      statementDay: statementDay, dueDay: dueDay, now: today);
  final statement = now.statementDate == today
      ? now.statementDate
      : now.nextStatementDate;
  final due = computeCreditCardCycle(
          statementDay: statementDay, dueDay: dueDay, now: statement)
      .dueDate;
  return (
    statement: statement,
    due: due,
    interestFreeDays: calendarDaysBetween(today, due),
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

  /// Paid toward the card since the statement was generated (bill payments,
  /// refunds), in the card's currency.
  final int paidSinceStatement;

  /// What is still owed on the statement: [statementAmount] less
  /// [paidSinceStatement]. Always positive — a fully paid statement produces
  /// no reminder at all.
  int get amountDue => statementAmount - paidSinceStatement;

  final DateTime dueDate;

  /// Whole days until [dueDate]; negative means overdue.
  final int daysUntilDue;

  const CreditCardReminder({
    required this.accountId,
    required this.accountName,
    required this.symbol,
    required this.statementAmount,
    required this.currentCycleSpend,
    this.paidSinceStatement = 0,
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
/// [spendInRange] returns the card's own-currency charges on [accountId] over
/// `[start, endExclusive)`. [paidInRange], when given, returns what was paid
/// into the card over the same kind of window; payments made since the
/// statement reduce what is due, and a statement paid in full produces no
/// reminder.
List<CreditCardReminder> creditCardReminders({
  required List<Account> accounts,
  required DateTime now,
  required int Function(int accountId, DateTime start, DateTime endExclusive)
      spendInRange,
  int Function(int accountId, DateTime start, DateTime endExclusive)?
      paidInRange,
  int withinDays = 7,
  int overdueGrace = 7,
}) {
  final today = DateTime(now.year, now.month, now.day);
  // Calendar arithmetic: a 24-hour Duration lands on 23:00 today on a
  // 25-hour daylight-saving day.
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  final out = <CreditCardReminder>[];
  for (final a in accounts) {
    if (!a.hasBillingCycle || a.id == null) continue;
    final id = a.id!;
    final cycle = computeCreditCardCycle(
      statementDay: a.statementDay!,
      dueDay: a.dueDay!,
      now: now,
    );

    CreditCardReminder? reminderFor(CreditCardCycle c, int daysUntilDue) {
      final statementAmount =
          spendInRange(id, c.billedCycleStart, c.billedUntil);
      // Nothing billed means nothing to pay — no reminder.
      if (statementAmount <= 0) return null;
      if (daysUntilDue > withinDays || daysUntilDue < -overdueGrace) {
        return null;
      }
      // Paying the bill used to change nothing: the reminder and the
      // dashboard kept saying it was due until the due date passed.
      final paid = paidInRange?.call(id, c.statementDate, tomorrow) ?? 0;
      if (paid >= statementAmount) return null;
      return CreditCardReminder(
        accountId: id,
        accountName: a.name,
        symbol: a.symbol,
        statementAmount: statementAmount,
        currentCycleSpend: spendInRange(id, c.billedUntil, tomorrow),
        paidSinceStatement: paid < 0 ? 0 : paid,
        dueDate: c.dueDate,
        daysUntilDue: daysUntilDue,
      );
    }

    // The statement before the latest one, while its due date is still
    // within the overdue grace. When the due date falls only a few days
    // before the next statement (statement on the 1st, due on the 28th), a
    // new statement used to replace an unpaid, overdue bill and the reminder
    // vanished. Payments since that older statement count towards it first.
    final previous = computeCreditCardCycle(
      statementDay: a.statementDay!,
      dueDay: a.dueDay!,
      now: cycle.statementDate.subtract(const Duration(days: 1)),
    );
    final previousDays = calendarDaysBetween(today, previous.dueDate);
    final overdue =
        previousDays < 0 ? reminderFor(previous, previousDays) : null;
    final reminder = overdue ?? reminderFor(cycle, cycle.daysUntilDue);
    if (reminder != null) out.add(reminder);
  }
  out.sort((x, y) => x.daysUntilDue.compareTo(y.daysUntilDue));
  return out;
}
