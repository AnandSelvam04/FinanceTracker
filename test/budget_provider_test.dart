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

  test('addBudget upserts rather than duplicating a category+month', () async {
    await provider.addBudget(
        Budget(category: 'Food', amount: 10000, year: 2026, month: 8));
    // Same category+month again should replace, not add a second row.
    await provider.addBudget(
        Budget(category: 'Food', amount: 25000, year: 2026, month: 8));

    final food = provider.budgets
        .where((b) => b.category == 'Food' && b.year == 2026 && b.month == 8)
        .toList();
    expect(food.length, 1);
    expect(food.single.amount, 25000);
  });

  test('copyBudgetsFromPreviousMonth copies caps and skips existing', () async {
    // July: two category caps + an overall cap.
    await provider.addBudget(
        Budget(category: 'Food', amount: 10000, year: 2026, month: 7));
    await provider.addBudget(
        Budget(category: 'Rent', amount: 50000, year: 2026, month: 7));
    await provider.addBudget(Budget(
        category: Budget.overallCategory,
        amount: 800000,
        year: 2026,
        month: 7));
    // August already has Food, so it must not be overwritten by the copy.
    await provider.addBudget(
        Budget(category: 'Food', amount: 99999, year: 2026, month: 8));

    final copied = await provider.copyBudgetsFromPreviousMonth(2026, 8);
    expect(copied, 2); // Rent + overall; Food skipped

    int amountFor(String c) => provider.budgets
        .firstWhere((b) => b.category == c && b.year == 2026 && b.month == 8)
        .amount;
    expect(amountFor('Rent'), 50000);
    expect(amountFor(Budget.overallCategory), 800000);
    // The pre-existing August Food cap is untouched.
    expect(amountFor('Food'), 99999);
  });
}
