import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';

/// The bulk writes screens used to send straight to the database now go
/// through ExpenseProvider, so the totals it holds follow each one.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'expense_provider_bulk_test.db';

  late ExpenseProvider provider;

  setUp(() async {
    await DBService().clearAll();
    provider = ExpenseProvider();
    await provider.ensureYearLoaded(2026);
  });

  tearDown(() async => DBService().clearAll());

  Expense row(int amount, {String category = 'Food', int? id}) => Expense(
        id: id,
        description: 'x',
        amount: amount,
        date: DateTime(2026, 5, 10),
        category: category,
        paymentMode: 'Cash',
        type: DbConstants.txExpense,
      );

  List<int> ids() => [for (final e in provider.expenses) e.id!];

  test('addExpenses and deleteExpenses move the totals', () async {
    expect(await provider.addExpenses([row(30000), row(20000)]), 2);
    expect(provider.totalForYear(2026), 50000);

    final saved = List.of(provider.expenses);
    expect(await provider.deleteExpenses(ids()), 2);
    expect(provider.totalForYear(2026), 0);

    // Undo puts the same rows back.
    await provider.addExpenses(saved);
    expect(provider.totalForYear(2026), 50000);
  });

  test('setCategory moves spending between categories', () async {
    await provider.addExpenses([row(30000), row(20000, category: 'Bills')]);
    await provider.setCategory(ids(), 'Travel');
    expect(provider.categoryTotalsForYear(2026), {'Travel': 50000});
  });

  test('renameCategory merges one category into another', () async {
    await provider.addExpenses([row(30000), row(20000, category: 'Dining')]);
    expect(
        await provider.renameCategory('Dining', 'Food',
            type: DbConstants.txExpense),
        1);
    expect(provider.categoryTotalsForYear(2026), {'Food': 50000});
  });

  test('splitExpense keeps the total and splits the categories', () async {
    await provider.addExpenses([row(50000)]);
    await provider.splitExpense(
        ids().single, [row(30000), row(20000, category: 'Household')]);
    expect(provider.expenses, hasLength(2));
    expect(provider.totalForYear(2026), 50000);
    expect(provider.categoryTotalsForYear(2026),
        {'Food': 30000, 'Household': 20000});
  });
}
