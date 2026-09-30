import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/investment.dart';
import 'package:finance_tracker/models/recurring_rule.dart';
import 'package:finance_tracker/providers/investment_provider.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/services/recurring_service.dart';
import 'package:finance_tracker/utils/billing_cycle.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Investments paid from an account: a bank balance drops, a credit card's
/// owed balance and statement grow, and net worth stays put.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'investment_account_test.db';

  setUp(() async => DBService().clearAll());
  tearDown(() async => DBService().clearAll());

  Future<int> balance(int id) async {
    final a = (await DBService().getAccounts()).singleWhere((a) => a.id == id);
    return DBService().getAccountBalance(a);
  }

  test('an investment paid from a bank lowers it; a withdrawal adds back',
      () async {
    final db = DBService();
    final bank = await db.insertAccount(
        Account(name: 'HDFC', type: 'bank', openingBalance: 1000000));
    await db.insertInvestment(Investment(
        name: 'Nifty',
        amount: 300000,
        date: DateTime(2026, 2, 5),
        type: 'Mutual Funds',
        accountId: bank));
    expect(await balance(bank), 700000);

    await db.insertInvestment(Investment(
        name: 'Nifty',
        amount: -100000,
        date: DateTime(2026, 2, 20),
        type: 'Mutual Funds',
        accountId: bank));
    expect(await balance(bank), 800000);

    // Money moved from the bank into the holding: net worth unchanged.
    final series = await db.netWorthSeries(1, now: DateTime(2026, 2, 25));
    expect(series.single.value, 1000000);
  });

  test('an investment on a credit card is owed and on the statement', () async {
    final db = DBService();
    final card = await db.insertAccount(Account(
        name: 'Amex', type: 'credit_card', statementDay: 10, dueDay: 25));
    await db.insertInvestment(Investment(
        name: 'Gold',
        amount: 50000,
        date: DateTime(2026, 3, 3),
        type: 'Gold',
        accountId: card));
    // Owed on the card.
    expect(await balance(card), -50000);

    final provider = InvestmentProvider();
    await provider.fetchInvestments();
    final reminders = creditCardReminders(
      accounts: await db.getAccounts(),
      now: DateTime(2026, 3, 20), // due on the 25th
      spendInRange: provider.chargedToAccountInRange,
    );
    expect(reminders.single.statementAmount, 50000);
    expect(reminders.single.accountName, 'Amex');
  });

  test('deleting the account unlinks its investments', () async {
    final db = DBService();
    final bank =
        await db.insertAccount(Account(name: 'Old bank', type: 'bank'));
    await db.insertInvestment(Investment(
        name: 'x',
        amount: 100,
        date: DateTime(2026, 1, 1),
        type: 'Stocks',
        accountId: bank));
    await db.deleteAccount(bank);
    expect((await db.getInvestments()).single.accountId, isNull);
  });

  test('a SIP paid from an account posts its contributions against it',
      () async {
    final db = DBService();
    final bank = await db.insertAccount(
        Account(name: 'HDFC', type: 'bank', openingBalance: 100000));
    await db.insertRecurringRule(RecurringRule(
      description: 'Index SIP',
      amount: 10000,
      category: 'Mutual Funds',
      frequency: DbConstants.freqMonthly,
      nextDue: DateTime(2026, 1, 5),
      isInvestment: true,
      accountId: bank,
    ));

    await RecurringService.instance
        .postDueTransactions(now: DateTime(2026, 2, 10));

    final posted = await db.getInvestments();
    expect(posted.length, 2);
    expect(posted.every((i) => i.accountId == bank), isTrue);
    expect(await balance(bank), 80000);
  });
  test('a foreign account is debited the converted amount', () async {
    final db = DBService();
    // A USD account at 83 base units per dollar, holding $1,000.
    final usd = await db.insertAccount(Account(
        name: 'Chase',
        type: 'bank',
        openingBalance: 100000,
        currency: '\$',
        rate: 83));
    // ₹8,300 (base currency) into a fund from it.
    await db.insertInvestment(Investment(
        name: 'S&P',
        amount: 830000,
        date: DateTime(2026, 4, 2),
        type: 'Stocks',
        accountId: usd));
    // $100 out, not $8,300.
    expect(await balance(usd), 90000);

    // Money only moved between holdings: net worth stays at $1,000 = ₹83,000.
    final series = await db.netWorthSeries(1, now: DateTime(2026, 4, 30));
    expect(series.single.value, 8300000);

    // On a card's statement it is the converted charge too.
    final provider = InvestmentProvider();
    await provider.fetchInvestments();
    expect(
        provider.chargedToAccountInRange(
            usd, DateTime(2026, 4, 1), DateTime(2026, 5, 1),
            rate: 83),
        10000);
  });
}
