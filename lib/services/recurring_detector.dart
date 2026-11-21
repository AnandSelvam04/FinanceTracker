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

  /// Spends in [history] that look like monthly bills or subscriptions not
  /// yet covered by a rule: the same payee at about the same amount in at
  /// least three of the last six months, one of them within the last 45
  /// days (so a cancelled one isn't offered). Payees in [known] — the
  /// descriptions of existing rules, and suggestions the user dismissed —
  /// are left out, compared case-insensitively. Biggest first.
  static List<RecurringSuggestion> suggestions(
    List<Expense> history, {
    Iterable<String> known = const [],
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now();
    final since = DateTime(now.year, now.month - 5);
    final recent = now.subtract(const Duration(days: 45));
    final skip = {for (final k in known) k.trim().toLowerCase()};

    final byPayee = <String, List<Expense>>{};
    for (final e in history) {
      if (e.type != DbConstants.txExpense || e.amount <= 0) continue;
      if (e.date.isBefore(since) || e.date.isAfter(now)) continue;
      final key = e.description.trim().toLowerCase();
      if (key.isEmpty || skip.contains(key)) continue;
      byPayee.putIfAbsent(key, () => []).add(e);
    }

    final found = <RecurringSuggestion>[];
    for (final rows in byPayee.values) {
      rows.sort((a, b) => b.date.compareTo(a.date));
      final latest = rows.first;
      if (latest.date.isBefore(recent)) continue;
      final tolerance = (latest.amount * _amountTolerance).round();
      final months = {
        for (final e in rows)
          if ((e.amount - latest.amount).abs() <= tolerance)
            _monthKey(e.date.year, e.date.month),
      };
      if (months.length < _minPriorMonths + 1) continue;
      found.add(RecurringSuggestion(
        description: latest.description.trim(),
        amount: latest.amount,
        category: latest.category,
        accountId: latest.accountId,
        lastDate: latest.date,
        months: months.length,
      ));
    }
    found.sort((a, b) => b.amount.compareTo(a.amount));
    return found;
  }

  static String _monthKey(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';
}

/// A spend that looks like a monthly bill, offered as a recurring rule.
class RecurringSuggestion {
  final String description;

  /// The latest charge, in its account's minor units.
  final int amount;
  final String category;
  final int? accountId;
  final DateTime lastDate;

  /// How many of the last six months carried it.
  final int months;

  const RecurringSuggestion({
    required this.description,
    required this.amount,
    required this.category,
    required this.accountId,
    required this.lastDate,
    required this.months,
  });

  /// When it would next fall due: a month after the latest charge, on the
  /// same day (clamped to the month's length), moved on past [today].
  DateTime nextDue(DateTime today) {
    var y = lastDate.year;
    var m = lastDate.month + 1;
    DateTime at() {
      final last = DateTime(y, m + 1, 0).day;
      return DateTime(y, m, lastDate.day > last ? last : lastDate.day);
    }

    var due = at();
    final start = DateTime(today.year, today.month, today.day);
    while (due.isBefore(start)) {
      m++;
      due = at();
    }
    return due;
  }
}
