import '../models/expense.dart';
import '../utils/db_constants.dart';

/// Decides whether an incoming transaction looks like a monthly subscription,
/// so the SMS importer can offer to turn it into a recurring rule.
///
/// Pure and testable on purpose: it takes the merchant, the amount, and the
/// transaction history, and never touches the database or Flutter.
class RecurringDetector {
  RecurringDetector._();

  /// Amounts this close count as "the same" charge. Subscriptions are usually
  /// billed to the paisa, but a tax tweak or FX charge can nudge the total, so
  /// a small tolerance avoids missing an obvious monthly bill.
  static const _amountTolerance = 0.05; // 5%

  /// How many distinct earlier months must carry the same charge before we
  /// call it recurring. Two prior months plus the one arriving now is three
  /// hits — enough of a pattern to suggest without crying wolf on a one-off.
  static const _minPriorMonths = 2;

  /// Whether [description] charged at about [amount] recurs monthly, judging by
  /// [history]: the same merchant (case-insensitive) appearing as a spend in at
  /// least [_minPriorMonths] distinct calendar months before the current one,
  /// each within [_amountTolerance] of [amount].
  ///
  /// Only expense rows count — income and transfers are not subscriptions — and
  /// the current month is excluded so the transaction being imported does not
  /// vote for itself.
  static bool looksMonthly(
    String description,
    int amount,
    List<Expense> history, {
    DateTime? asOf,
  }) {
    final desc = description.trim().toLowerCase();
    if (desc.isEmpty || amount <= 0) return false;
    final now = asOf ?? DateTime.now();
    final currentKey = _monthKey(now.year, now.month);
    final tolerance = (amount * _amountTolerance).round();

    final months = <String>{};
    for (final e in history) {
      if (e.type != DbConstants.txExpense) continue;
      if (e.description.trim().toLowerCase() != desc) continue;
      if ((e.amount - amount).abs() > tolerance) continue;
      final key = _monthKey(e.date.year, e.date.month);
      if (key == currentKey) continue;
      months.add(key);
    }
    return months.length >= _minPriorMonths;
  }

  static String _monthKey(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';
}
