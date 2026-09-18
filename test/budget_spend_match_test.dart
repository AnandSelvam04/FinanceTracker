import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';

/// ExpenseProvider.spentForCategoryInMonth is the single source of truth for
/// budget "spent". It must match the category leniently (case/whitespace) so a
/// budget still tracks spend filed under a slightly different spelling, and it
/// must convert foreign-currency rows to the base currency like the caps are.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'budget_spend_match_test.db';

  final date = DateTime(2026, 5, 10);
  late ExpenseProvider provider;

  setUp(() async {
    await DBService().clearAll();
    provider = ExpenseProvider();
  });

  tearDown(() async => DBService().clearAll());

  Future<void> add(int amount, {required String category, int? accountId}) =>
      DBService().insertExpense(Expense(
        description: 'x',
        amount: amount,
        date: date,
        category: category,
        paymentMode: 'Cash',
        type: DbConstants.txExpense,
        accountId: accountId,
      ));

  test('matches spend across case and whitespace differences', () async {
    await add(30000, category: 'Groceries');
    await add(10000, category: 'groceries');
    await add(5000, category: ' Groceries ');
    await add(9999, category: 'Food'); // unrelated category, must not count
    await provider.ensureYearLoaded(2026);

    // A budget typed any of these ways sees the full 45000.
    expect(provider.spentForCategoryInMonth(2026, 5, 'Groceries'), 45000);
    expect(provider.spentForCategoryInMonth(2026, 5, 'groceries'), 45000);
    expect(provider.spentForCategoryInMonth(2026, 5, '  GROCERIES'), 45000);
  });

  test('is scoped to the given month and returns 0 when nothing matches',
      () async {
    await add(10000, category: 'Food');
    await provider.ensureYearLoaded(2026);

    expect(provider.spentForCategoryInMonth(2026, 5, 'Food'), 10000);
    expect(provider.spentForCategoryInMonth(2026, 6, 'Food'), 0);
    expect(provider.spentForCategoryInMonth(2026, 5, 'Transport'), 0);
  });

  test('converts foreign-currency spend to the base currency', () async {
    final usd =
        await DBService().insertAccount(Account(name: 'US', type: 'bank'));
    await add(10000, category: 'Travel', accountId: usd);
    await provider.ensureYearLoaded(2026);

    // At rate 1.0 the raw amount stands.
    expect(provider.spentForCategoryInMonth(2026, 5, 'Travel'), 10000);

    // With a rate, the category spend is converted just like the total is.
    provider.syncAccountRates({usd: 2.0});
    final expected = provider
        .spendingForMonth(2026, 5)
        .where((e) => e.category == 'Travel')
        .map(provider.baseAmountOf)
        .fold<int>(0, (a, b) => a + b);
    expect(provider.spentForCategoryInMonth(2026, 5, 'Travel'), expected);
    expect(provider.spentForCategoryInMonth(2026, 5, 'Travel'),
        isNot(10000));
  });
}
