import '../models/expense.dart';
import '../utils/db_constants.dart';
import 'db_service.dart';

/// Posts due recurring transactions when the app is opened or resumed.
/// No background workers — data only needs to be correct while the app
/// is in use, and a catch-up loop handles gaps between launches.
class RecurringService {
  RecurringService._();
  static final RecurringService instance = RecurringService._();

  bool _running = false;

  /// Advances a due date by one period, keeping monthly/yearly rules
  /// anchored to their original day-of-month where possible.
  static DateTime nextDate(DateTime current, String frequency, int anchorDay) {
    switch (frequency) {
      case DbConstants.freqDaily:
        return current.add(const Duration(days: 1));
      case DbConstants.freqWeekly:
        return current.add(const Duration(days: 7));
      case DbConstants.freqMonthly:
        return _addMonths(current, 1, anchorDay);
      case DbConstants.freqYearly:
        return _addMonths(current, 12, anchorDay);
      default:
        return current.add(const Duration(days: 1));
    }
  }

  static DateTime _addMonths(DateTime date, int months, int anchorDay) {
    final targetMonthIndex = date.year * 12 + (date.month - 1) + months;
    final year = targetMonthIndex ~/ 12;
    final month = targetMonthIndex % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = anchorDay > lastDay ? lastDay : anchorDay;
    return DateTime(year, month, day);
  }

  /// Posts every occurrence due on or before today for all enabled rules.
  /// Returns the number of transactions inserted. Idempotent per call.
  Future<int> postDueTransactions({DateTime? now}) async {
    if (_running) return 0;
    _running = true;
    try {
      final today = now ?? DateTime.now();
      final endOfToday = DateTime(today.year, today.month, today.day, 23, 59, 59);
      final db = DBService();
      final rules = await db.getRecurringRules();
      var posted = 0;

      for (final rule in rules) {
        if (!rule.enabled) continue;
        var due = rule.nextDue;
        // Catch-up: materialize one transaction per elapsed period.
        final occurrences = <Expense>[];
        while (!due.isAfter(endOfToday)) {
          occurrences.add(Expense(
            description: rule.description,
            amount: rule.amount,
            date: due,
            category: rule.category,
            paymentMode: 'Other',
            type: rule.type,
            accountId: rule.accountId,
          ));
          due = nextDate(due, rule.frequency, rule.anchorDay);
        }
        if (occurrences.isEmpty) continue;
        // Insert the occurrences and advance nextDue in one transaction so a
        // crash in between can't double-post them on the next launch.
        await db.postRecurringOccurrences(
            occurrences, rule.copyWith(nextDue: due));
        posted += occurrences.length;
      }
      return posted;
    } finally {
      _running = false;
    }
  }
}
