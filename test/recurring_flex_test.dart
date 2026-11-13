import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/recurring_rule.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/services/notification_service.dart';
import 'package:finance_tracker/services/recurring_service.dart';
import 'package:finance_tracker/utils/alerts.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;

  setUp(() async {
    await DBService().close();
    DBService.dbNameOverride = 'recurring_flex_test.db';
    await DBService().clearAll();
  });

  tearDown(() async {
    await DBService().clearAll();
  });

  Future<RecurringRule> saved(RecurringRule rule) async {
    final id = await DBService().insertRecurringRule(rule);
    return (await DBService().getRecurringRules())
        .firstWhere((r) => r.id == id);
  }

  group('every N periods', () {
    test('steps a fortnight, a quarter and half a year', () {
      final d = DateTime(2026, 1, 31);
      expect(
          RecurringService.nextDate(d, DbConstants.freqWeekly, 31, interval: 2),
          DateTime(2026, 2, 14));
      // Anchored on the 31st: April has 30 days, July has 31.
      final apr = RecurringService.nextDate(d, DbConstants.freqMonthly, 31,
          interval: 3);
      expect(apr, DateTime(2026, 4, 30));
      expect(
          RecurringService.nextDate(apr, DbConstants.freqMonthly, 31,
              interval: 3),
          DateTime(2026, 7, 31));
      expect(
          RecurringService.nextDate(d, DbConstants.freqMonthly, 31,
              interval: 6),
          DateTime(2026, 7, 31));
    });

    test('a quarterly rule catches up one row a quarter', () async {
      await saved(RecurringRule(
        description: 'Insurance',
        amount: 500000,
        category: 'Insurance',
        frequency: DbConstants.freqMonthly,
        interval: 3,
        nextDue: DateTime(2026, 1, 10),
      ));
      final posted = await RecurringService.instance
          .postDueTransactions(now: DateTime(2026, 8, 1));
      expect(posted, 3);
      final dates = (await DBService().getExpenses()).map((e) => e.date);
      expect(
          dates,
          containsAll([
            DateTime(2026, 1, 10),
            DateTime(2026, 4, 10),
            DateTime(2026, 7, 10),
          ]));
      expect((await DBService().getRecurringRules()).single.nextDue,
          DateTime(2026, 10, 10));
    });

    test('is named in words', () {
      expect(RecurringRule.describeFrequency(DbConstants.freqMonthly, 1),
          'Monthly');
      expect(RecurringRule.describeFrequency(DbConstants.freqWeekly, 2),
          'Every 2 weeks');
      expect(RecurringRule.describeFrequency(DbConstants.freqMonthly, 3),
          'Every 3 months');
    });
  });

  group('recurring transfers', () {
    test('move money between the two accounts without spending', () async {
      final db = DBService();
      final bank = await db.insertAccount(
          Account(name: 'Bank', type: 'bank', openingBalance: 10000000));
      final loan = await db.insertAccount(
          Account(name: 'Car loan', type: 'loan', openingBalance: -5000000));
      await saved(RecurringRule(
        description: 'Car EMI',
        amount: 1000000,
        category: 'Transfer',
        type: DbConstants.txTransfer,
        accountId: bank,
        toAccountId: loan,
        frequency: DbConstants.freqMonthly,
        nextDue: DateTime(2026, 5, 5),
      ));
      final posted = await RecurringService.instance
          .postDueTransactions(now: DateTime(2026, 6, 20));
      expect(posted, 2);
      final rows = await db.getExpenses();
      expect(rows.every((e) => e.isTransfer), isTrue);
      expect(rows.every((e) => e.toAccountId == loan), isTrue);
      final accounts = {for (final a in await db.getAccounts()) a.id: a};
      expect(await db.getAccountBalance(accounts[bank]!), 8000000);
      expect(await db.getAccountBalance(accounts[loan]!), -3000000);
    });

    test('convert between currencies', () async {
      final db = DBService();
      final inr = await db.insertAccount(Account(name: 'Bank', type: 'bank'));
      final usd = await db.insertAccount(
          Account(name: 'USD', type: 'bank', currency: r'$', rate: 80));
      await saved(RecurringRule(
        description: 'To USD',
        amount: 800000,
        category: 'Transfer',
        type: DbConstants.txTransfer,
        accountId: inr,
        toAccountId: usd,
        frequency: DbConstants.freqMonthly,
        nextDue: DateTime(2026, 5, 5),
      ));
      await RecurringService.instance
          .postDueTransactions(now: DateTime(2026, 5, 5));
      expect((await db.getExpenses()).single.toAmount, 10000);
    });

    test('are paused, not half-posted, when an account is deleted', () async {
      final db = DBService();
      final bank = await db.insertAccount(Account(name: 'Bank', type: 'bank'));
      final loan = await db.insertAccount(Account(name: 'Loan', type: 'loan'));
      await saved(RecurringRule(
        description: 'EMI',
        amount: 1000,
        category: 'Transfer',
        type: DbConstants.txTransfer,
        accountId: bank,
        toAccountId: loan,
        frequency: DbConstants.freqMonthly,
        nextDue: DateTime(2026, 5, 5),
      ));
      await db.deleteAccount(loan);
      final rule = (await db.getRecurringRules()).single;
      expect(rule.enabled, isFalse);
      expect(rule.toAccountId, isNull);
      expect(rule.accountId, bank);

      // Switched back on without its account, it posts nothing and stays due.
      await db.updateRecurringRule(rule.copyWith(enabled: true));
      final posted = await RecurringService.instance
          .postDueTransactions(now: DateTime(2026, 6, 20));
      expect(posted, 0);
      expect(await db.getExpenses(), isEmpty);
      expect(
          (await db.getRecurringRules()).single.nextDue, DateTime(2026, 5, 5));
    });
  });

  group('ask me each time', () {
    RecurringRule bill() => RecurringRule(
          description: 'Electricity',
          amount: 150000,
          category: 'Bills',
          frequency: DbConstants.freqMonthly,
          nextDue: DateTime(2026, 5, 5),
          askFirst: true,
        );

    test('never posts by itself and shows as waiting', () async {
      final rule = await saved(bill());
      final posted = await RecurringService.instance
          .postDueTransactions(now: DateTime(2026, 7, 1));
      expect(posted, 0);
      expect(await DBService().getExpenses(), isEmpty);

      final alert =
          upcomingBills(rules: [rule], now: DateTime(2026, 7, 1)).single;
      expect(alert.needsConfirm, isTrue);
      expect(alert.isOverdue, isTrue);
    });

    test('records the confirmed amount on its due date and moves on', () async {
      final rule = await saved(bill());
      expect(
          await RecurringService.instance
              .postOnce(rule, amount: 183450, now: DateTime(2026, 5, 9)),
          isTrue);
      final row = (await DBService().getExpenses()).single;
      expect(row.amount, 183450);
      expect(row.date, DateTime(2026, 5, 5));
      final after = (await DBService().getRecurringRules()).single;
      expect(after.nextDue, DateTime(2026, 6, 5));
      // The usual amount is kept for next time.
      expect(after.amount, 150000);
    });

    test('confirmed early is dated the day it was confirmed', () async {
      final rule = await saved(bill());
      await RecurringService.instance
          .postOnce(rule, amount: 1000, now: DateTime(2026, 5, 2, 10));
      expect((await DBService().getExpenses()).single.date,
          DateTime(2026, 5, 2, 10));
    });

    test('an income rule waiting to be confirmed is listed too', () {
      final rule = RecurringRule(
        description: 'Freelance',
        amount: 100,
        category: 'Salary',
        type: DbConstants.txIncome,
        frequency: DbConstants.freqMonthly,
        nextDue: DateTime(2026, 5, 5),
        askFirst: true,
      );
      expect(upcomingBills(rules: [rule], now: DateTime(2026, 5, 5)),
          hasLength(1));
    });
  });

  group('skipping', () {
    test('moves past one occurrence without posting it', () async {
      final rule = await saved(RecurringRule(
        description: 'Gym',
        amount: 200000,
        category: 'Health',
        frequency: DbConstants.freqMonthly,
        nextDue: DateTime(2026, 5, 31),
      ));
      await RecurringService.instance.skipOnce(rule);
      expect(await DBService().getExpenses(), isEmpty);
      final after = (await DBService().getRecurringRules()).single;
      expect(after.nextDue, DateTime(2026, 6, 30));
      expect(after.anchorDay, 31);
      expect(after.enabled, isTrue);
    });

    test('ends the rule when the skipped one was its last', () async {
      final rule = await saved(RecurringRule(
        description: 'Course',
        amount: 100,
        category: 'Education',
        frequency: DbConstants.freqMonthly,
        nextDue: DateTime(2026, 5, 5),
        endDate: DateTime(2026, 5, 20),
      ));
      await RecurringService.instance.skipOnce(rule);
      expect((await DBService().getRecurringRules()).single.enabled, isFalse);
    });
  });

  test('posted rows carry the account\'s payment mode', () async {
    final db = DBService();
    final card =
        await db.insertAccount(Account(name: 'Card', type: 'credit_card'));
    await saved(RecurringRule(
      description: 'Netflix',
      amount: 64900,
      category: 'Bills',
      accountId: card,
      frequency: DbConstants.freqMonthly,
      nextDue: DateTime(2026, 5, 5),
    ));
    await RecurringService.instance
        .postDueTransactions(now: DateTime(2026, 5, 5));
    expect((await db.getExpenses()).single.paymentMode, 'Credit Card');
  });

  group('bill reminders', () {
    RecurringRule rule({
      int? id = 7,
      String type = DbConstants.txExpense,
      String frequency = DbConstants.freqMonthly,
      DateTime? endDate,
      bool isInvestment = false,
    }) =>
        RecurringRule(
          id: id,
          description: 'Rent',
          amount: 100,
          category: 'Housing',
          type: type,
          frequency: frequency,
          nextDue: DateTime(2026, 5, 31),
          endDate: endDate,
          isInvestment: isInvestment,
        );

    test('cover the coming occurrences, not only the next', () {
      final dues = NotificationService.billReminderDues(rule());
      expect(dues, hasLength(NotificationService.billRemindersAhead));
      expect(dues.first, DateTime(2026, 5, 31));
      expect(dues[1], DateTime(2026, 6, 30));
      expect(dues.last, DateTime(2026, 10, 31));
    });

    test('stop at the end date', () {
      expect(
          NotificationService.billReminderDues(
              rule(endDate: DateTime(2026, 7, 31))),
          hasLength(3));
    });

    test('a daily rule gets one', () {
      expect(
          NotificationService.billReminderDues(
              rule(frequency: DbConstants.freqDaily)),
          hasLength(1));
    });

    test('transfers are bills; income and SIPs are not', () {
      expect(
          NotificationService.billReminderDues(
              rule(type: DbConstants.txTransfer)),
          isNotEmpty);
      expect(
          NotificationService.billReminderDues(
              rule(type: DbConstants.txIncome)),
          isEmpty);
      expect(NotificationService.billReminderDues(rule(isInvestment: true)),
          isEmpty);
      expect(NotificationService.billReminderDues(rule(id: null)), isEmpty);
    });
  });

  test('a v22 database gains the new rule columns with safe defaults',
      () async {
    await DBService().close();
    DBService.dbNameOverride = 'recurring_v23_migration_test.db';
    final path =
        join(await getDatabasesPath(), 'recurring_v23_migration_test.db');
    await databaseFactory.deleteDatabase(path);
    final v22 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 22,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE recurring_rules(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              description TEXT,
              amount INTEGER,
              category TEXT,
              type TEXT NOT NULL DEFAULT 'expense',
              accountId INTEGER,
              frequency TEXT NOT NULL,
              nextDue TEXT NOT NULL,
              anchorDay INTEGER NOT NULL DEFAULT 1,
              enabled INTEGER NOT NULL DEFAULT 1,
              endDate TEXT,
              isInvestment INTEGER NOT NULL DEFAULT 0
            )
          ''');
        },
      ),
    );
    await v22.insert('recurring_rules', {
      'description': 'Rent',
      'amount': 1500000,
      'category': 'Housing',
      'frequency': 'monthly',
      'nextDue': DateTime(2026, 12, 1).toIso8601String(),
    });
    await v22.close();

    final rule = (await DBService().getRecurringRules()).single;
    expect(rule.description, 'Rent');
    expect(rule.interval, 1);
    expect(rule.askFirst, isFalse);
    expect(rule.toAccountId, isNull);
    await DBService().close();
    await databaseFactory.deleteDatabase(path);
  });
}
