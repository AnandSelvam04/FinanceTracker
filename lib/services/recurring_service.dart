import '../models/account.dart';
import '../models/expense.dart';
import '../models/investment.dart';
import '../models/recurring_rule.dart';
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
  ///
  /// [interval] is how many periods to step: 2 with weekly is a fortnight, 3
  /// with monthly a quarter.
  static DateTime nextDate(DateTime current, String frequency, int anchorDay,
      {int interval = 1}) {
    final n = interval < 1 ? 1 : interval;
    switch (frequency) {
      case DbConstants.freqDaily:
        return _addDays(current, n);
      case DbConstants.freqWeekly:
        return _addDays(current, 7 * n);
      case DbConstants.freqMonthly:
        return _addMonths(current, n, anchorDay);
      case DbConstants.freqYearly:
        return _addMonths(current, 12 * n, anchorDay);
      default:
        return _addDays(current, n);
    }
  }

  /// The occurrence of [rule] after [current].
  static DateTime nextFor(RecurringRule rule, DateTime current) =>
      nextDate(current, rule.frequency, rule.anchorDay,
          interval: rule.interval);

  /// The transaction one occurrence of [rule] posts on [date], or null for a
  /// transfer rule that has lost one of its two accounts: half a transfer
  /// would move money out of (or into) nowhere.
  ///
  /// [amount] replaces the rule's own, for a bill confirmed at this time's
  /// figure. [accounts] is every account by id.
  static Expense? occurrence(
      RecurringRule rule, DateTime date, Map<int, Account> accounts,
      {int? amount}) {
    final value = amount ?? rule.amount;
    final from = accounts[rule.accountId];
    if (!rule.isTransfer) {
      return Expense(
        description: rule.description,
        amount: value,
        date: date,
        category: rule.category,
        // What the account pays with, so a rule's rows count under UPI or
        // the card in "How you paid" rather than all under Other.
        paymentMode: rule.type == DbConstants.txIncome
            ? 'Other'
            : switch (from?.type) {
                'cash' => 'Cash',
                'credit_card' => 'Credit Card',
                'upi' => 'UPI',
                _ => 'Other',
              },
        type: rule.type,
        accountId: rule.accountId,
      );
    }
    final to = accounts[rule.toAccountId];
    if (from == null || to == null || from.id == to.id) return null;
    return Expense(
      description: rule.description,
      amount: value,
      date: date,
      category: 'Transfer',
      paymentMode: 'Other',
      type: DbConstants.txTransfer,
      accountId: from.id,
      toAccountId: to.id,
      // Accounts in different currencies: what arrives is the amount sent,
      // converted through both accounts' rates to the base currency.
      toAmount: from.symbol == to.symbol || to.rate <= 0
          ? null
          : (value * from.rate / to.rate).round(),
    );
  }

  static Future<Map<int, Account>> _accountsById(DBService db) async =>
      {for (final a in await db.getAccounts()) a.id!: a};

  /// Whether the occurrence after [next] falls past the rule's end date, so
  /// the rule has nothing left to post.
  static bool _finishedAt(RecurringRule rule, DateTime next) =>
      rule.endDate != null && next.isAfter(_endOfDay(rule.endDate!));

  /// Posts the occurrence [rule] is waiting on and moves it to the next one.
  /// [amount] is what it came to this time (the rule's own when left out).
  /// The row is dated the day it fell due, or today when confirmed early.
  /// Returns false when there was nothing to post (see [occurrence]).
  Future<bool> postOnce(RecurringRule rule,
      {int? amount, DateTime? now}) async {
    final db = DBService();
    final today = now ?? DateTime.now();
    final date = rule.nextDue.isAfter(today) ? today : rule.nextDue;
    final next = nextFor(rule, rule.nextDue);
    final advanced = rule.copyWith(
        nextDue: next, enabled: _finishedAt(rule, next) ? false : null);
    if (rule.isInvestment) {
      await db.postRecurringInvestments([
        Investment(
          name: rule.description,
          amount: amount ?? rule.amount,
          date: date,
          type: rule.category,
          accountId: rule.accountId,
        ),
      ], advanced);
      return true;
    }
    final tx = occurrence(rule, date, await _accountsById(db), amount: amount);
    if (tx == null) return false;
    await db.postRecurringOccurrences([tx], advanced);
    return true;
  }

  /// Moves [rule] past its next occurrence without posting it: the month the
  /// gym was closed, a bill someone else paid.
  Future<void> skipOnce(RecurringRule rule) async {
    final next = nextFor(rule, rule.nextDue);
    await DBService().postRecurringOccurrences(
        const [],
        rule.copyWith(
            nextDue: next, enabled: _finishedAt(rule, next) ? false : null));
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

  /// The last instant of [d]'s calendar day, so an end date is inclusive of
  /// occurrences scheduled at any time on that day.
  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59);

  static DateTime _minDate(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

  static DateTime _addMonths(DateTime date, int months, int anchorDay) {
    final targetMonthIndex = date.year * 12 + (date.month - 1) + months;
    final year = targetMonthIndex ~/ 12;
    final month = targetMonthIndex % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = anchorDay > lastDay ? lastDay : anchorDay;
    // Keep the wall-clock time, as [_addDays] does: dropping it moved every
    // monthly and yearly occurrence after the first to midnight.
    return DateTime(year, month, day, date.hour, date.minute, date.second,
        date.millisecond, date.microsecond);
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
      final accounts = await _accountsById(db);
      var posted = 0;

      for (final rule in rules) {
        if (!rule.enabled) continue;
        // Waits for its amount to be confirmed; see [postOnce].
        if (rule.askFirst) continue;
        // Never post past the rule's end date (inclusive of that whole day).
        final endLimit = rule.endDate == null
            ? endOfToday
            : _minDate(_endOfDay(rule.endDate!), endOfToday);
        var due = rule.nextDue;
        // Catch-up: one due date per elapsed period.
        final dueDates = <DateTime>[];
        while (
            !due.isAfter(endLimit) && dueDates.length < maxOccurrencesPerRun) {
          dueDates.add(due);
          due = nextFor(rule, due);
        }
        // The rule is done once its next occurrence would fall past the end
        // date; disable it so it stops being considered on later launches.
        final finished =
            rule.endDate != null && due.isAfter(_endOfDay(rule.endDate!));
        if (dueDates.isEmpty) {
          if (finished) {
            await db.postRecurringOccurrences(
                const [], rule.copyWith(nextDue: due, enabled: false));
          }
          continue;
        }
        final advanced =
            rule.copyWith(nextDue: due, enabled: finished ? false : null);
        // Insert the occurrences and advance nextDue in one transaction so a
        // crash in between can't double-post them on the next launch. A SIP
        // rule files into the investments ledger; every other rule posts a
        // transaction.
        if (rule.isInvestment) {
          await db.postRecurringInvestments([
            for (final d in dueDates)
              Investment(
                name: rule.description,
                amount: rule.amount,
                date: d,
                type: rule.category,
                accountId: rule.accountId,
              ),
          ], advanced);
        } else {
          final rows = [
            for (final d in dueDates) occurrence(rule, d, accounts),
          ].nonNulls.toList();
          // A transfer rule missing an account posts nothing and stays where
          // it is, so it is still due once the account is picked again.
          if (rows.isEmpty) continue;
          await db.postRecurringOccurrences(rows, advanced);
        }
        posted += dueDates.length;
      }
      return posted;
    } finally {
      _running = false;
    }
  }
}
