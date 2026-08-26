import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';

/// The per-period aggregates are memoized until the data (or an exchange rate)
/// changes. These tests prove the cache returns correct numbers, reuses the
/// cached instance while nothing changes, and is invalidated on every path that
/// can move a total.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'expense_provider_cache_test.db';

  final date = DateTime(2026, 5, 10);
  late ExpenseProvider provider;

  setUp(() async {
    await DBService().clearAll();
    provider = ExpenseProvider();
  });

  tearDown(() async => DBService().clearAll());

  Future<void> add(int amount, {String category = 'Food', int? accountId}) =>
      DBService().insertExpense(Expense(
        description: 'x',
        amount: amount,
        date: date,
        category: category,
        paymentMode: 'Cash',
        type: DbConstants.txExpense,
        accountId: accountId,
      ));

  test('reuses the cached map while nothing changes, with correct totals',
      () async {
    await add(30000, category: 'Food');
    await add(10000, category: 'Bills');
    await provider.ensureYearLoaded(2026);

    final m1 = provider.categoryTotalsForMonth(2026, 5);
    final m2 = provider.categoryTotalsForMonth(2026, 5);

    expect(m1['Food'], 30000);
    expect(m1['Bills'], 10000);
    // Second call returns the very same cached instance, not a recomputation.
    expect(identical(m1, m2), isTrue);
    expect(provider.totalForMonth(2026, 5), 40000);
  });

  test('adding an expense invalidates the cache', () async {
    await add(10000);
    await provider.ensureYearLoaded(2026);

    expect(provider.totalForMonth(2026, 5), 10000);
    final before = provider.categoryTotalsForMonth(2026, 5);

    await provider.addExpense(Expense(
      description: 'y',
      amount: 5000,
      date: date,
      category: 'Food',
      paymentMode: 'Cash',
      type: DbConstants.txExpense,
    ));

    // Recomputed, not served stale.
    expect(provider.totalForMonth(2026, 5), 15000);
    final after = provider.categoryTotalsForMonth(2026, 5);
    expect(identical(before, after), isFalse);
    expect(after['Food'], 15000);
  });

  test('changing an exchange rate invalidates the cache', () async {
    final accountId =
        await DBService().insertAccount(Account(name: 'US', type: 'bank'));
    await add(10000, accountId: accountId);
    await provider.ensureYearLoaded(2026);

    final unrated = provider.totalForMonth(2026, 5); // rate defaults to 1.0
    expect(unrated, 10000);

    provider.syncAccountRates({accountId: 2.0});
    final rated = provider.totalForMonth(2026, 5);

    // The cache was cleared, so the total reflects the new rate.
    final expected = provider
        .expensesForMonth(2026, 5)
        .map(provider.baseAmountOf)
        .fold<int>(0, (a, b) => a + b);
    expect(rated, expected);
    expect(rated, isNot(unrated));
  });
}
