import '../models/account.dart';
import '../models/expense.dart';

/// How a period's spending was paid for.
enum PayMethod {
  creditCard('Credit cards'),
  bank('Bank / debit card'),
  upi('UPI'),
  cash('Cash'),
  other('Other');

  final String label;
  const PayMethod(this.label);
}

/// One account's (or the unlinked rows') share of a [PayMethodTotal].
class PayMethodPart {
  /// Null for spending recorded without an account.
  final int? accountId;
  final int total;
  const PayMethodPart({required this.accountId, required this.total});
}

/// Spending paid one way over a period, with the accounts it came from.
class PayMethodTotal {
  final PayMethod method;

  /// Net, in base-currency minor units (refunds already taken off).
  final int total;

  /// Largest first.
  final List<PayMethodPart> parts;
  const PayMethodTotal(
      {required this.method, required this.total, required this.parts});
}

/// The way [e] was paid.
///
/// A charge on a credit-card account is card spending however it was made
/// (a RuPay card used over UPI is still on the card's bill). Otherwise the
/// recorded payment mode decides — UPI or cash from a bank account is UPI or
/// cash — and then the account's type, so a bank row with no mode is bank.
PayMethod payMethodOf(Expense e, Account? account) {
  if (account?.type == 'credit_card') return PayMethod.creditCard;
  switch (e.paymentMode) {
    case 'Credit Card':
      return PayMethod.creditCard;
    case 'UPI':
      return PayMethod.upi;
    case 'Cash':
      return PayMethod.cash;
    case 'Debit Card':
      return PayMethod.bank;
  }
  return switch (account?.type) {
    'bank' => PayMethod.bank,
    'upi' => PayMethod.upi,
    'cash' => PayMethod.cash,
    _ => PayMethod.other,
  };
}

/// Splits the expenses in [rows] by how they were paid — credit cards, bank,
/// UPI, cash — largest first, each with the accounts behind it. Methods and
/// accounts whose refunds cancel their spending are left out.
List<PayMethodTotal> paymentSplit(
  Iterable<Expense> rows,
  int Function(Expense) baseAmountOf,
  Account? Function(int? id) accountById,
) {
  final byMethod = <PayMethod, Map<int?, int>>{};
  for (final e in rows) {
    if (!e.isExpense) continue;
    final method = payMethodOf(e, accountById(e.accountId));
    final parts = byMethod[method] ??= {};
    parts[e.accountId] = (parts[e.accountId] ?? 0) + baseAmountOf(e);
  }

  final out = <PayMethodTotal>[];
  for (final entry in byMethod.entries) {
    final parts = [
      for (final p in entry.value.entries)
        if (p.value > 0) PayMethodPart(accountId: p.key, total: p.value),
    ]..sort((a, b) => b.total.compareTo(a.total));
    final total = parts.fold<int>(0, (s, p) => s + p.total);
    if (total > 0) {
      out.add(PayMethodTotal(method: entry.key, total: total, parts: parts));
    }
  }
  out.sort((a, b) => b.total.compareTo(a.total));
  return out;
}
