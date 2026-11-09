part of '../db_service.dart';

/// Investment contributions and each type's recorded market value.
extension InvestmentQueries on DBService {
  Future<int> insertInvestment(Investment investment) async {
    final db = await database;
    return await db.insert(DbConstants.tableInvestments, investment.toMap());
  }

  Future<List<Investment>> getInvestments() async {
    final db = await database;
    final maps = await db.query(DbConstants.tableInvestments,
        orderBy: '${DbConstants.colDate} DESC');
    final investments = <Investment>[];
    for (final map in maps) {
      try {
        investments.add(Investment.fromMap(map));
      } catch (e, st) {
        AppLogger.error('Failed to parse investment row', e, st);
      }
    }
    return investments;
  }

  Future<int> updateInvestment(Investment investment) async {
    final db = await database;
    return await db.update(DbConstants.tableInvestments, investment.toMap(),
        where: '${DbConstants.colId} = ?', whereArgs: [investment.id]);
  }

  Future<int> deleteInvestment(int id) async {
    final db = await database;
    return await db.delete(DbConstants.tableInvestments,
        where: '${DbConstants.colId} = ?', whereArgs: [id]);
  }

  /// Reassigns every contribution filed under [from] to [to], for correcting a
  /// mis-typed category. Returns the number of rows moved. A no-op (0 rows) if
  /// the type has no contributions or [from] equals [to].
  ///
  /// Monthly SIP rules filing into [from] move with it, in the same
  /// transaction. Moving only the past contributions let the next SIP recreate
  /// the type that had just been merged away.
  Future<int> reassignInvestmentType(String from, String to) async {
    if (from == to) return 0;
    final db = await database;
    return db.transaction((txn) async {
      final moved = await txn.update(
        DbConstants.tableInvestments,
        {DbConstants.colType: to},
        where: '${DbConstants.colType} = ?',
        whereArgs: [from],
      );
      await txn.update(
        DbConstants.tableRecurringRules,
        {DbConstants.colCategory: to},
        where:
            '${DbConstants.colIsInvestment} = 1 AND ${DbConstants.colCategory} = ?',
        whereArgs: [from],
      );
      // The old type's market value described holdings that are now part of
      // another type; it no longer means anything on its own.
      await txn.delete(DbConstants.tableInvestmentValues,
          where: '${DbConstants.colType} = ?', whereArgs: [from]);
      return moved;
    });
  }

  Future<void> clearInvestments() async {
    final db = await database;
    await db.delete(DbConstants.tableInvestments);
    await db.delete(DbConstants.tableInvestmentValues);
  }

  /// The current market value recorded for each investment type.
  Future<Map<String, InvestmentValue>> getInvestmentValues() async {
    final db = await database;
    final rows = await db.query(DbConstants.tableInvestmentValues);
    return {
      for (final r in rows)
        r[DbConstants.colType] as String: InvestmentValue(
          amount: (r[DbConstants.colAmount] as num).toInt(),
          asOf: DateTime.parse(r[DbConstants.colDate] as String),
        ),
    };
  }

  /// Records [type]'s current market value, or clears it when [value] is
  /// null.
  Future<void> setInvestmentValue(String type, InvestmentValue? value) async {
    final db = await database;
    if (value == null) {
      await db.delete(DbConstants.tableInvestmentValues,
          where: '${DbConstants.colType} = ?', whereArgs: [type]);
      return;
    }
    await db.insert(
      DbConstants.tableInvestmentValues,
      {
        DbConstants.colType: type,
        DbConstants.colAmount: value.amount,
        DbConstants.colDate: value.asOf.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// The investment-ledger counterpart to [postRecurringOccurrences]: inserts a
  /// SIP rule's due contributions and advances the rule in one transaction.
  Future<void> postRecurringInvestments(
      List<Investment> contributions, RecurringRule advancedRule) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final inv in contributions) {
        await txn.insert(DbConstants.tableInvestments, inv.toMap());
      }
      await txn.update(DbConstants.tableRecurringRules, advancedRule.toMap(),
          where: '${DbConstants.colId} = ?', whereArgs: [advancedRule.id]);
    });
  }
}
