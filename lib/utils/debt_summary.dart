import '../models/account.dart';

/// Where one loan or loan to someone stands: how much was borrowed (or
/// lent) in all, how much has come back, and what is still outstanding.
class DebtSummary {
  final Account account;

  /// Borrowed, or lent, in all: the starting amount plus every later top-up.
  final int total;

  /// Repaid so far (to the lender, or by the person you lent to).
  final int repaid;

  /// Still to repay, or still owed to you. Zero once settled.
  final int outstanding;

  /// Paid back beyond what was owed. Zero in the usual case.
  final int overpaid;

  const DebtSummary({
    required this.account,
    required this.total,
    required this.repaid,
    required this.outstanding,
    this.overpaid = 0,
  });

  /// Share repaid, 0–1. Null when nothing was borrowed or lent.
  double? get progress =>
      total <= 0 ? null : (repaid / total).clamp(0.0, 1.0).toDouble();

  bool get settled => outstanding == 0 && total > 0;
}

/// [account]'s summary from its [balance] and the money that moved in and
/// out of it ([io], from `DBService.getAccountInOut`). Null for accounts
/// that are neither a loan nor money lent.
///
/// A loan's balance is negative while money is owed: borrowing moves money
/// out of it (into a bank account), repaying moves money in. Money lent is
/// the mirror image.
DebtSummary? debtSummary(
    Account account, int balance, ({int inflow, int outflow})? io) {
  final inflow = io?.inflow ?? 0, outflow = io?.outflow ?? 0;
  final opening = account.openingBalance;
  if (account.isLoan) {
    final total = (opening < 0 ? -opening : 0) + outflow;
    return DebtSummary(
      account: account,
      total: total,
      repaid: inflow + (opening > 0 ? opening : 0),
      outstanding: balance < 0 ? -balance : 0,
      overpaid: balance > 0 ? balance : 0,
    );
  }
  if (account.isLent) {
    final total = (opening > 0 ? opening : 0) + inflow;
    return DebtSummary(
      account: account,
      total: total,
      repaid: outflow + (opening < 0 ? -opening : 0),
      outstanding: balance > 0 ? balance : 0,
      overpaid: balance < 0 ? -balance : 0,
    );
  }
  return null;
}
