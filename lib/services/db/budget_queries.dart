part of '../db_service.dart';

/// Monthly category budgets.
extension BudgetQueries on DBService {
  Future<int> insertBudget(Budget budget) async {
    final db = await database;
    return await db.insert(DbConstants.tableBudgets, budget.toMap());
  }

  /// Inserts a budget, or updates the amount of the existing one for the same
  /// category+year+month. Keeps a category from having two budget rows in one
  /// month (the plain insert path allowed silent duplicates that lookups then
  /// resolved arbitrarily).
  ///
  /// The category matches ignoring case and surrounding whitespace, the same
  /// rule [updateBudget] and the spend lookups use: otherwise a budget for
  /// "food" was added next to an existing "Food" and the month had two caps.
  Future<void> upsertBudget(Budget budget) async {
    final db = await database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        DbConstants.tableBudgets,
        columns: [DbConstants.colId],
        where: '${DbConstants.colYear} = ? AND ${DbConstants.colMonth} = ? '
            'AND lower(trim(${DbConstants.colCategory})) = lower(trim(?))',
        whereArgs: [budget.year, budget.month, budget.category],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert(DbConstants.tableBudgets, budget.toMap());
      } else {
        await txn.update(
          DbConstants.tableBudgets,
          {DbConstants.colAmount: budget.amount},
          where: '${DbConstants.colId} = ?',
          whereArgs: [existing.first[DbConstants.colId]],
        );
      }
    });
  }

  Future<List<Budget>> getBudgets() async {
    final db = await database;
    final maps = await db.query(DbConstants.tableBudgets);
    return maps.map((map) => Budget.fromMap(map)).toList();
  }

  /// Saves an edited budget. When the edit moves it onto a category and
  /// month that already has a budget, that other row is replaced: otherwise
  /// the month ended up with two caps for one category, and whichever loaded
  /// first silently won.
  Future<int> updateBudget(Budget budget) async {
    final db = await database;
    return db.transaction((txn) async {
      await txn.delete(
        DbConstants.tableBudgets,
        where: '${DbConstants.colId} != ? AND ${DbConstants.colYear} = ? '
            'AND ${DbConstants.colMonth} = ? '
            'AND lower(trim(${DbConstants.colCategory})) = lower(trim(?))',
        whereArgs: [budget.id, budget.year, budget.month, budget.category],
      );
      return txn.update(DbConstants.tableBudgets, budget.toMap(),
          where: '${DbConstants.colId} = ?', whereArgs: [budget.id]);
    });
  }

  Future<int> deleteBudget(int id) async {
    final db = await database;
    return await db.delete(DbConstants.tableBudgets,
        where: '${DbConstants.colId} = ?', whereArgs: [id]);
  }

  Future<void> clearBudgets() async {
    final db = await database;
    await db.delete(DbConstants.tableBudgets);
  }
}
