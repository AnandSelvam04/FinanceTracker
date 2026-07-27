import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/models/recurring_rule.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/services/recurring_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Expense _expense(String category, String type, DateTime date) => Expense(
      description: 'test',
      amount: 10,
      date: date,
      category: category,
      paymentMode: 'Cash',
      type: type,
    );

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;

  setUp(() async {
    DBService.dbNameOverride = 'recurring_test.db';
    await DBService().clearAll();
  });

  tearDown(() async {
    await DBService().clearAll();
  });

  group('nextDate advancement', () {
    test('daily and weekly', () {
      final d = DateTime(2026, 3, 10);
      expect(RecurringService.nextDate(d, DbConstants.freqDaily, 10),
          DateTime(2026, 3, 11));
      expect(RecurringService.nextDate(d, DbConstants.freqWeekly, 10),
          DateTime(2026, 3, 17));
    });

    test('monthly clamps to short months (Jan 31 -> Feb 28)', () {
      final jan31 = DateTime(2026, 1, 31);
      final feb = RecurringService.nextDate(jan31, DbConstants.freqMonthly, 31);
      expect(feb, DateTime(2026, 2, 28));
      // Anchored back to 31 in March.
      final mar = RecurringService.nextDate(feb, DbConstants.freqMonthly, 31);
      expect(mar, DateTime(2026, 3, 31));
    });

    test('yearly handles Feb 29 leap anchor', () {
      final leap = DateTime(2024, 2, 29);
      final next = RecurringService.nextDate(leap, DbConstants.freqYearly, 29);
      expect(next, DateTime(2025, 2, 28));
    });
  });

  group('postDueTransactions', () {
    test('catch-up posts one row per elapsed period, then is idempotent',
        () async {
      final db = DBService();
      // Monthly rule that first came due 3 months before "now".
      final now = DateTime(2026, 4, 15);
      await db.insertRecurringRule(RecurringRule(
        description: 'Rent',
        amount: 1000,
        category: 'Bills',
        frequency: DbConstants.freqMonthly,
        nextDue: DateTime(2026, 1, 15),
      ));

      final posted =
          await RecurringService.instance.postDueTransactions(now: now);
      expect(posted, 4); // Jan, Feb, Mar, Apr

      final expenses = await db.getExpenses();
      expect(expenses.length, 4);
      expect(expenses.every((e) => e.type == DbConstants.txExpense), isTrue);

      // Rule advanced past today.
      final rule = (await db.getRecurringRules()).first;
      expect(rule.nextDue.isAfter(now), isTrue);

      // Second call posts nothing.
      final again =
          await RecurringService.instance.postDueTransactions(now: now);
      expect(again, 0);
      expect((await db.getExpenses()).length, 4);
    });

    test('disabled rules are not posted', () async {
      final db = DBService();
      await db.insertRecurringRule(RecurringRule(
        description: 'Paused',
        amount: 50,
        category: 'Other',
        frequency: DbConstants.freqDaily,
        nextDue: DateTime(2026, 1, 1),
        enabled: false,
      ));
      final posted = await RecurringService.instance
          .postDueTransactions(now: DateTime(2026, 1, 10));
      expect(posted, 0);
      expect(await db.getExpenses(), isEmpty);
    });
  });

  group('frequentCategories', () {
    test('orders by usage count and excludes other types', () async {
      final db = DBService();
      final recent = DateTime.now().subtract(const Duration(days: 5));
      Future<void> add(String category, String type) => db.insertExpense(
            _expense(category, type, recent),
          );
      await add('Food', DbConstants.txExpense);
      await add('Food', DbConstants.txExpense);
      await add('Food', DbConstants.txExpense);
      await add('Transport', DbConstants.txExpense);
      await add('Salary', DbConstants.txIncome);

      final result =
          await db.frequentCategories(DbConstants.txExpense, days: 90);
      expect(result.first, 'Food');
      expect(result.contains('Transport'), isTrue);
      expect(result.contains('Salary'), isFalse);
    });
  });

  group('nextDate is DST-safe', () {
    // Duration(days: 1) adds 24 hours, which lands on the wrong wall-clock
    // time (and sometimes the wrong date) on the two days a year a local day
    // is 23 or 25 hours long. Calendar arithmetic keeps the time of day.
    test('daily keeps the wall-clock time and advances exactly one date', () {
      var due = DateTime(2026, 3, 7, 0, 0);
      for (var i = 0; i < 10; i++) {
        final next = RecurringService.nextDate(due, DbConstants.freqDaily, 7);
        expect(next.hour, 0, reason: 'hour drifted on step $i');
        expect(next.minute, 0);
        expect(next.difference(DateTime(due.year, due.month, due.day)).inDays,
            greaterThan(0));
        expect(next.day, DateTime(due.year, due.month, due.day + 1).day);
        due = next;
      }
    });

    test('weekly advances seven calendar days, same weekday and time', () {
      final due = DateTime(2026, 10, 29, 9, 30);
      final next = RecurringService.nextDate(due, DbConstants.freqWeekly, 29);
      expect(next, DateTime(2026, 11, 5, 9, 30));
      expect(next.weekday, due.weekday);
    });

    test('daily rolls over month and year boundaries', () {
      expect(RecurringService.nextDate(DateTime(2026, 1, 31),
              DbConstants.freqDaily, 31),
          DateTime(2026, 2, 1));
      expect(RecurringService.nextDate(DateTime(2026, 12, 31),
              DbConstants.freqDaily, 31),
          DateTime(2027, 1, 1));
    });
  });

  group('catch-up is bounded', () {
    test('a long-overdue daily rule posts at most the cap in one run',
        () async {
      final db = DBService();
      // nextDue three years back: unbounded catch-up would materialise ~1,100
      // transactions in one launch-blocking pass.
      await db.insertRecurringRule(RecurringRule(
        description: 'Coffee',
        amount: 100,
        category: 'Food',
        frequency: DbConstants.freqDaily,
        nextDue: DateTime(2023, 1, 1),
      ));

      final posted = await RecurringService.instance
          .postDueTransactions(now: DateTime(2026, 1, 1));

      expect(posted, RecurringService.maxOccurrencesPerRun);
      expect((await db.getExpenses()).length,
          RecurringService.maxOccurrencesPerRun);

      // The rule resumes where it left off, so nothing is lost.
      final rule = (await db.getRecurringRules()).single;
      expect(rule.nextDue.isAfter(DateTime(2023, 1, 1)), isTrue);

      final more = await RecurringService.instance
          .postDueTransactions(now: DateTime(2026, 1, 1));
      expect(more, greaterThan(0));
    });
  });
}
