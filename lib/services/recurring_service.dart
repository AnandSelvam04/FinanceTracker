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
        return _addDays(current, 1);
      case DbConstants.freqWeekly:
        return _addDays(current, 7);
      case DbConstants.freqMonthly:
        return _addMonths(current, 1, anchorDay);
      case DbConstants.freqYearly:
        return _addMonths(current, 12, anchorDay);
      default:
        return _addDays(current, 1);
    }
  }

  /// Adds [days] calendar days, keeping the wall-clock time.
  ///
  /// `Duration(days: 1)` adds 24 hours, which is wrong on the two days a year
  /// a local day is 23 or 25 hours long: a rule due at 00:00 crossing
  /// spring-forward landed at 01:00 the *same* date, so the catch-up loop
  /// could post an extra occurrence or skip one. The DateTime constructor
  /// normalises overflow (day 32 becomes the 1st of the next month) and works
  /// in local calendar terms, so it doesn't drift.
  static DateTime _addDays(DateTime date, int days) => DateTime(
        date.year,
        date.month,
        date.day + days,
        date.hour,
        date.minute,
        date.second,
        date.millisecond,
        date.microsecond,
      );

  static DateTime _addMonths(DateTime date, int months, int anchorDay) {
    final targetMonthIndex = date.year * 12 + (date.month - 1) + months;
    final year = targetMonthIndex ~/ 12;
    final month = targetMonthIndex % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = anchorDay > lastDay ? lastDay : anchorDay;
    return DateTime(year, month, day);
  }

  /// Most occurrences a single rule will post in one run.
  ///
  /// The catch-up loop is unbounded by nature: a daily rule whose `nextDue` is
  /// years in the past — a restored old backup, or a device clock that jumped
  /// — would otherwise materialise thousands of transactions in one
  /// launch-blocking pass. Posting stops at the cap and resumes from there on
  /// the next launch, so nothing is lost, just spread out.
  static const maxOccurrencesPerRun = 366;

  /// Posts every occurrence due on or before today for all enabled rules,
  /// up to [maxOccurrencesPerRun] per rule.
  /// Returns the number of transactions inserted. Idempotent per call.
  Future<int> postDueTransactions({DateTime? now}) async {
    if (_running) return 0;
    _running = true;
    try {
      final today = now ?? DateTime.now();
      final endOfToday =
          DateTime(today.year, today.month, today.day, 23, 59, 59);
      final db = DBService();
      final rules = await db.getRecurringRules();
      var posted = 0;

      for (final rule in rules) {
        if (!rule.enabled) continue;
        var due = rule.nextDue;
        // Catch-up: materialize one transaction per elapsed period.
        final occurrences = <Expense>[];
        while (!due.isAfter(endOfToday) &&
            occurrences.length < maxOccurrencesPerRun) {
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
