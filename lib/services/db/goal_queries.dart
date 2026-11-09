part of '../db_service.dart';

/// Savings goals.
extension GoalQueries on DBService {
  Future<int> insertGoal(SavingsGoal goal) async {
    final db = await database;
    return await db.insert(DbConstants.tableGoals, goal.toMap());
  }

  Future<List<SavingsGoal>> getGoals() async {
    final db = await database;
    final maps = await db.query(DbConstants.tableGoals);
    return maps.map(SavingsGoal.fromMap).toList();
  }

  Future<int> updateGoal(SavingsGoal goal) async {
    final db = await database;
    return await db.update(DbConstants.tableGoals, goal.toMap(),
        where: '${DbConstants.colId} = ?', whereArgs: [goal.id]);
  }

  Future<int> deleteGoal(int id) async {
    final db = await database;
    return await db.delete(DbConstants.tableGoals,
        where: '${DbConstants.colId} = ?', whereArgs: [id]);
  }

  Future<void> clearGoals() async {
    final db = await database;
    await db.delete(DbConstants.tableGoals);
  }
}
