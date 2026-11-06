import '../models/account.dart';
import 'alerts.dart' show calendarDaysBetween;
import 'billing_cycle.dart';

/// Where one credit card stands today: what has gone on it since the last
/// statement, what is owed on it, and the state of the last bill. Pure, so the
/// dashboard's Credit cards section can be tested without widgets.
class CreditCardSummary {
  final Account account;

  /// Start (inclusive) of the spending window [cycleSpend] covers: the day
  /// after the last statement, or — for a card with no billing cycle set — the
  /// first of this month.
  final DateTime periodStart;

  /// Charged to the card since [periodStart], in the card's own currency
  /// (minor units). Refunds on the card take it down.
  final int cycleSpend;

  /// What the card's balance says is owed (a negative balance, made
  /// positive). Zero when nothing is owed.
  final int owed;

  /// Money sitting on the card beyond what is owed — an overpaid bill or a
  /// refund after payment. Zero in the usual case.
  final int credit;

  /// The billing cycle, when the card has statement and due days set.
  final CreditCardCycle? cycle;

  /// Billed on the last statement; zero without a [cycle].
  final int statementAmount;

  /// Paid towards the card since the last statement.
  final int paidSinceStatement;

  /// Whole days from today to the last statement's due date; negative means
  /// overdue. Null without a [cycle].
  final int? daysUntilDue;

  const CreditCardSummary({
    required this.account,
    required this.periodStart,
    required this.cycleSpend,
    required this.owed,
    this.credit = 0,
    this.cycle,
    this.statementAmount = 0,
    this.paidSinceStatement = 0,
    this.daysUntilDue,
  });

  bool get hasCycle => cycle != null;

  /// What is still to pay on the last statement.
  int get dueRemaining {
    final left = statementAmount - paidSinceStatement;
    return left > 0 ? left : 0;
  }

  /// The last statement billed something and it has all been paid.
  bool get billPaid => statementAmount > 0 && dueRemaining == 0;

  bool get isOverdue => dueRemaining > 0 && (daysUntilDue ?? 0) < 0;
}

/// One summary per credit-card account, the cards with a bill still to pay
/// first (soonest due date first), then the rest by name.
///
/// [spendInRange] and [paidInRange] are the same window queries the bill
/// reminders use (see [creditCardReminders]); [balanceOf] is the card's
/// current balance in its own currency, null while it is still loading.
List<CreditCardSummary> creditCardSummaries({
  required List<Account> accounts,
  required DateTime now,
  required int Function(int accountId, DateTime start, DateTime endExclusive)
      spendInRange,
  required int Function(int accountId, DateTime start, DateTime endExclusive)
      paidInRange,
  required int? Function(Account account) balanceOf,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  final out = <CreditCardSummary>[];
  for (final a in accounts) {
    if (a.type != 'credit_card' || a.id == null) continue;
    final id = a.id!;
    final balance = balanceOf(a) ?? 0;
    final owed = balance < 0 ? -balance : 0;
    final credit = balance > 0 ? balance : 0;

    if (!a.hasBillingCycle) {
      final start = DateTime(today.year, today.month, 1);
      out.add(CreditCardSummary(
        account: a,
        periodStart: start,
        cycleSpend: spendInRange(id, start, tomorrow),
        owed: owed,
        credit: credit,
      ));
      continue;
    }

    final cycle = computeCreditCardCycle(
        statementDay: a.statementDay!, dueDay: a.dueDay!, now: now);
    final paid = paidInRange(id, cycle.statementDate, tomorrow);
    out.add(CreditCardSummary(
      account: a,
      periodStart: cycle.billedUntil,
      cycleSpend: spendInRange(id, cycle.billedUntil, tomorrow),
      owed: owed,
      credit: credit,
      cycle: cycle,
      statementAmount:
          spendInRange(id, cycle.billedCycleStart, cycle.billedUntil),
      paidSinceStatement: paid < 0 ? 0 : paid,
      daysUntilDue: calendarDaysBetween(today, cycle.dueDate),
    ));
  }

  out.sort((x, y) {
    final xDue = x.dueRemaining > 0, yDue = y.dueRemaining > 0;
    if (xDue != yDue) return xDue ? -1 : 1;
    if (xDue) {
      final byDays = x.daysUntilDue!.compareTo(y.daysUntilDue!);
      if (byDays != 0) return byDays;
    }
    return x.account.name.toLowerCase().compareTo(y.account.name.toLowerCase());
  });
  return out;
}
