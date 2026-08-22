import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/budget.dart';
import 'package:finance_tracker/providers/budget_provider.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers the overall-monthly-budget helpers layered on top of the existing
/// per-category budgets.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'budget_provider_test.db';

  late BudgetProvider provider;

  setUp(() async {
    await DBService().clearAll();
    provider = BudgetProvider();
  });

  tearDown(() async => DBService().clearAll());

  test('overall budget is stored and read back for its month', () async {
    await provider.addBudget(Budget(
        category: Budget.overallCategory,
        amount: 5000000,
        year: 2026,
        month: 8));
    await provider.fetchBudgets();

    expect(provider.overallBudget(2026, 8), 5000000);
    expect(provider.overallBudgetRow(2026, 8)?.isOverall, isTrue);
    // A month with no overall cap reads as zero.
    expect(provider.overallBudget(2026, 9), 0);
  });

  test('categoryBudgets excludes the overall cap', () async {
    await provider.addBudget(
        Budget(category: 'Food', amount: 10000, year: 2026, month: 8));
    await provider.addBudget(Budget(
        category: Budget.overallCategory,
        amount: 5000000,
        year: 2026,
        month: 8));
    await provider.fetchBudgets();

    expect(provider.budgets.length, 2);
    expect(provider.categoryBudgets.map((b) => b.category), ['Food']);
  });
}
