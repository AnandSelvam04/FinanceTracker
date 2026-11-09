part of '../db_service.dart';

/// Recurring rules, posting what they make due, and quick-add templates.
extension RecurringQueries on DBService {
  Future<int> insertRecurringRule(RecurringRule rule) async {
    final db = await database;
    return await db.insert(DbConstants.tableRecurringRules, rule.toMap());
  }

  Future<List<RecurringRule>> getRecurringRules() async {
    final db = await database;
    final maps = await db.query(DbConstants.tableRecurringRules,
        orderBy: DbConstants.colNextDue);
    return maps.map((map) => RecurringRule.fromMap(map)).toList();
  }

  Future<int> updateRecurringRule(RecurringRule rule) async {
    final db = await database;
    return await db.update(DbConstants.tableRecurringRules, rule.toMap(),
        where: '${DbConstants.colId} = ?', whereArgs: [rule.id]);
  }

  Future<int> deleteRecurringRule(int id) async {
    final db = await database;
    return await db.delete(DbConstants.tableRecurringRules,
        where: '${DbConstants.colId} = ?', whereArgs: [id]);
  }

  Future<void> clearRecurringRules() async {
    final db = await database;
    await db.delete(DbConstants.tableRecurringRules);
  }

  /// Atomically posts materialized recurring [occurrences] and advances the
  /// rule's nextDue, so a crash can't insert the transactions without moving
  /// the due date (which would double-post them on the next launch).
  Future<void> postRecurringOccurrences(
      List<Expense> occurrences, RecurringRule advancedRule) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final e in occurrences) {
        await txn.insert(DbConstants.tableExpenses, e.toMap());
      }
      await txn.update(DbConstants.tableRecurringRules, advancedRule.toMap(),
          where: '${DbConstants.colId} = ?', whereArgs: [advancedRule.id]);
    });
  }

  Future<int> insertTemplate(TxTemplate template) async {
    final db = await database;
    return await db.insert(DbConstants.tableTemplates, template.toMap());
  }

  Future<List<TxTemplate>> getTemplates() async {
    final db = await database;
    final maps = await db.query(DbConstants.tableTemplates,
        orderBy: DbConstants.colName);
    return maps.map((map) => TxTemplate.fromMap(map)).toList();
  }

  Future<int> deleteTemplate(int id) async {
    final db = await database;
    return await db.delete(DbConstants.tableTemplates,
        where: '${DbConstants.colId} = ?', whereArgs: [id]);
  }

  Future<void> clearTemplates() async {
    final db = await database;
    await db.delete(DbConstants.tableTemplates);
  }
}
