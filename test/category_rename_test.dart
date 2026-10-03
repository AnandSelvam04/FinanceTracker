import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/budget.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/models/recurring_rule.dart';
import 'package:finance_tracker/models/tx_template.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'category_rename_test.db';

  final db = DBService();
  setUp(() async => db.clearAll());
  tearDown(() async => db.clearAll());

  Future<void> add(String category,
          {String type = DbConstants.txExpense, int amount = 100}) =>
      db.insertExpense(Expense(
        description: 'x',
        amount: amount,
        date: DateTime(2026, 5, 10),
        category: category,
        paymentMode: 'Cash',
        type: type,
      ));

  Future<List<String>> categories(String type) async =>
      [for (final u in await db.categoryUsage(type)) u.category];

  test('categoryUsage lists each stored spelling with its count', () async {
    await add('Food');
    await add('Food');
    await add('food ');
    await add('Salary', type: DbConstants.txIncome);
    final usage = await db.categoryUsage(DbConstants.txExpense);
    expect(usage.first, (category: 'Food', count: 2));
    expect(usage.map((u) => u.category), containsAll(['Food', 'food ']));
    expect(await categories(DbConstants.txIncome), ['Salary']);
  });

  test('rename moves every spelling, rules and templates of that type only',
      () async {
    await add('Grocery');
    await add(' grocery');
    await add('Grocery', type: DbConstants.txIncome);
    await db.insertRecurringRule(RecurringRule(
        description: 'Veg box',
        amount: 500,
        category: 'grocery',
        frequency: 'weekly',
        nextDue: DateTime(2026, 6, 1)));
    await db.insertTemplate(TxTemplate(
        name: 'Milk', description: 'Milk', amount: 60, category: 'Grocery'));

    final moved = await db.renameCategory('Grocery', 'Groceries',
        type: DbConstants.txExpense);

    expect(moved, 2);
    expect(await categories(DbConstants.txExpense), ['Groceries']);
    // The income row with the same name is a different category.
    expect(await categories(DbConstants.txIncome), ['Grocery']);
    expect((await db.getRecurringRules()).single.category, 'Groceries');
    expect((await db.getTemplates()).single.category, 'Groceries');
  });

  test('merging sums budgets that collide in the same month', () async {
    await add('Grocery');
    await add('Groceries');
    await db.insertBudget(
        Budget(category: 'Grocery', amount: 2000, year: 2026, month: 5));
    await db.insertBudget(
        Budget(category: 'grocery', amount: 500, year: 2026, month: 5));
    await db.insertBudget(
        Budget(category: 'Groceries', amount: 3000, year: 2026, month: 5));
    await db.insertBudget(
        Budget(category: 'Grocery', amount: 1000, year: 2026, month: 6));
    await db.insertBudget(Budget(
        category: Budget.overallCategory, amount: 9000, year: 2026, month: 5));

    await db.renameCategory('Grocery', 'Groceries',
        type: DbConstants.txExpense);

    final budgets = await db.getBudgets();
    int capFor(String c, int month) =>
        budgets.where((b) => b.category == c && b.month == month).single.amount;
    expect(capFor('Groceries', 5), 5500);
    expect(capFor('Groceries', 6), 1000);
    expect(capFor(Budget.overallCategory, 5), 9000);
    expect(budgets, hasLength(3));
    expect(await categories(DbConstants.txExpense), ['Groceries']);
  });

  test('blank or unchanged names are a no-op', () async {
    await add('Food');
    expect(
        await db.renameCategory('Food', '  ', type: DbConstants.txExpense), 0);
    expect(await db.renameCategory('Food', 'Food', type: DbConstants.txExpense),
        0);
    expect(await categories(DbConstants.txExpense), ['Food']);
  });
}
