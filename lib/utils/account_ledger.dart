import '../models/expense.dart';
import '../models/investment.dart';

/// One row of an account's statement: what moved the balance, by how much,
/// and the balance right after it.
class AccountLedgerEntry {
  /// The transaction ([Expense]) or investment ([Investment]) behind the row.
  final Object source;
  final DateTime date;

  /// Change to the account's balance, in its own currency's minor units:
  /// negative for money out, positive for money in.
  final int delta;

  /// The account's balance after this row (and every earlier one).
  final int balanceAfter;

  const AccountLedgerEntry({
    required this.source,
    required this.date,
    required this.delta,
    required this.balanceAfter,
  });
}

/// Builds the statement for [accountId], newest first, with a running
/// balance that starts from [openingBalance].
///
/// Uses the same rules as `DBService.getAccountFlows`, so the newest row's
/// balance equals the balance shown on the Accounts screen: income adds,
/// expenses (a refund is a negative expense) and outgoing transfers subtract,
/// incoming transfers add what was received, and investments paid from the
/// account subtract (a withdrawal, stored negative, adds back).
List<AccountLedgerEntry> accountLedger({
  required int accountId,
  required int openingBalance,
  required Iterable<Expense> transactions,
  Iterable<Investment> investments = const [],
}) {
  final moves = <(Object, DateTime, int)>[];
  for (final e in transactions) {
    var delta = 0;
    if (e.accountId == accountId) {
      delta += e.isIncome ? e.amount : -e.amount;
    }
    if (e.isTransfer && e.toAccountId == accountId) {
      delta += e.receivedAmount;
    }
    if (e.accountId == accountId || e.toAccountId == accountId) {
      moves.add((e, e.date, delta));
    }
  }
  for (final i in investments) {
    if (i.accountId == accountId) moves.add((i, i.date, -i.amount));
  }
  // Oldest first to accumulate; stable on ties so same-day rows keep order.
  final ordered = [
    for (var k = 0; k < moves.length; k++) (k, moves[k]),
  ]..sort((a, b) {
      final byDate = a.$2.$2.compareTo(b.$2.$2);
      return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
    });
  var balance = openingBalance;
  final entries = <AccountLedgerEntry>[];
  for (final (_, (source, date, delta)) in ordered) {
    balance += delta;
    entries.add(AccountLedgerEntry(
        source: source, date: date, delta: delta, balanceAfter: balance));
  }
  return entries.reversed.toList();
}
