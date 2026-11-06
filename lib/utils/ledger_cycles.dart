import 'account_ledger.dart';
import 'billing_cycle.dart';

/// One billing cycle of a credit card's statement: the rows dated inside it,
/// what was charged, and what was paid or refunded.
class LedgerCycle {
  /// First day of the cycle (inclusive).
  final DateTime start;

  /// The statement that closes the cycle — its last day. In the future for
  /// the open cycle (see [isOpen]).
  final DateTime statementDate;

  /// When the statement closing this cycle is due.
  final DateTime dueDate;

  /// Whether the cycle is still running: its statement hasn't been generated.
  final bool isOpen;

  /// Charged in the cycle: purchases, cash withdrawals, investments bought on
  /// the card (money out of the account), in its own currency.
  final int charged;

  /// Paid into the card in the cycle: bill payments, refunds, cashback.
  final int paidIn;

  /// The cycle's rows, newest first.
  final List<AccountLedgerEntry> entries;

  const LedgerCycle({
    required this.start,
    required this.statementDate,
    required this.dueDate,
    required this.isOpen,
    required this.charged,
    required this.paidIn,
    required this.entries,
  });
}

/// Groups a card's [ledger] (newest first, as [accountLedger] builds it) into
/// billing cycles, newest first. A cycle runs from the day after one
/// statement to the next statement day inclusive, as [computeCreditCardCycle]
/// bills it. Only cycles with rows in them are returned.
List<LedgerCycle> ledgerByCycle(
  List<AccountLedgerEntry> ledger, {
  required int statementDay,
  required int dueDay,
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final byStatement = <DateTime, List<AccountLedgerEntry>>{};
  final cycles = <DateTime, CreditCardCycle>{};
  for (final entry in ledger) {
    final day = DateTime(entry.date.year, entry.date.month, entry.date.day);
    // The statement that bills this day: this month's, unless the day is
    // after it, in which case next month's.
    var cycle = computeCreditCardCycle(
        statementDay: statementDay, dueDay: dueDay, now: day);
    if (cycle.statementDate.isBefore(day)) {
      cycle = computeCreditCardCycle(
          statementDay: statementDay,
          dueDay: dueDay,
          now: cycle.nextStatementDate);
    }
    final key = cycle.statementDate;
    cycles[key] = cycle;
    (byStatement[key] ??= []).add(entry);
  }

  final out = <LedgerCycle>[];
  for (final key in byStatement.keys.toList()..sort((a, b) => b.compareTo(a))) {
    final entries = byStatement[key]!;
    var charged = 0, paidIn = 0;
    for (final e in entries) {
      if (e.delta < 0) {
        charged += -e.delta;
      } else {
        paidIn += e.delta;
      }
    }
    final cycle = cycles[key]!;
    out.add(LedgerCycle(
      start: cycle.billedCycleStart,
      statementDate: key,
      dueDate: cycle.dueDate,
      isOpen: key.isAfter(today),
      charged: charged,
      paidIn: paidIn,
      entries: entries,
    ));
  }
  return out;
}
