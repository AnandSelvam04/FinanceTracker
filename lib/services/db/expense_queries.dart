part of '../db_service.dart';

/// Transactions (expenses, income and transfers): reading and writing rows,
/// bulk edits, and the category lists and renames built on them.
extension ExpenseQueries on DBService {
  Future<int> insertExpense(Expense expense) async {
    final db = await database;
    try {
      return await db.insert(DbConstants.tableExpenses, expense.toMap());
    } catch (e) {
      throw Exception('Failed to insert expense: $e');
    }
  }

  /// Inserts many rows in one transaction, so a bulk operation (CSV import)
  /// either lands completely or not at all. Returns the number inserted.
  Future<int> insertExpenses(List<Expense> expenses) async {
    if (expenses.isEmpty) return 0;
    final db = await database;
    try {
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final e in expenses) {
          batch.insert(DbConstants.tableExpenses, e.toMap());
        }
        await batch.commit(noResult: true);
      });
      return expenses.length;
    } catch (e) {
      throw Exception('Failed to import expenses: $e');
    }
  }

  /// Replaces one transaction with several that sum to it, in a single
  /// transaction so a split can't leave the original deleted with no parts (or
  /// the parts inserted with the original still there). The caller guarantees
  /// the parts add up to the original amount.
  Future<void> splitExpense(int originalId, List<Expense> parts) async {
    if (parts.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(DbConstants.tableExpenses,
          where: '${DbConstants.colId} = ?', whereArgs: [originalId]);
      final batch = txn.batch();
      for (final e in parts) {
        batch.insert(DbConstants.tableExpenses, e.toMap());
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Expense>> getExpenses() async {
    final db = await database;
    try {
      final maps = await db.query(DbConstants.tableExpenses,
          orderBy: '${DbConstants.colDate} DESC');
      final expenses = <Expense>[];
      for (final map in maps) {
        try {
          expenses.add(Expense.fromMap(map));
        } catch (e, st) {
          // If parsing a row fails, log it and continue
          AppLogger.error('Failed to parse expense row', e, st);
        }
      }
      return expenses;
    } catch (e) {
      throw Exception('Failed to fetch expenses: $e');
    }
  }

  Future<List<Expense>> getExpensesByYear(int year) async {
    final db = await database;
    try {
      final start = DateTime(year).toIso8601String();
      final end = DateTime(year + 1).toIso8601String();
      final maps = await db.query(
        DbConstants.tableExpenses,
        where: '${DbConstants.colDate} >= ? AND ${DbConstants.colDate} < ?',
        whereArgs: [start, end],
        orderBy: '${DbConstants.colDate} DESC',
      );
      final expenses = <Expense>[];
      for (final map in maps) {
        try {
          expenses.add(Expense.fromMap(map));
        } catch (e) {
          AppLogger.error('Failed to parse expense row', e);
        }
      }
      return expenses;
    } catch (e) {
      throw Exception('Failed to fetch expenses for year $year: $e');
    }
  }

  /// Returns transaction rows whose date falls in the half-open interval
  /// [start, end). Filtering happens in SQL so callers can page through data
  /// without loading every row into memory.
  Future<List<Expense>> getExpensesByDateRange(
      DateTime start, DateTime end) async {
    final db = await database;
    try {
      final maps = await db.query(
        DbConstants.tableExpenses,
        where: '${DbConstants.colDate} >= ? AND ${DbConstants.colDate} < ?',
        whereArgs: [start.toIso8601String(), end.toIso8601String()],
        orderBy: '${DbConstants.colDate} DESC',
      );
      final expenses = <Expense>[];
      for (final map in maps) {
        try {
          expenses.add(Expense.fromMap(map));
        } catch (e) {
          AppLogger.error('Failed to parse expense row', e);
        }
      }
      return expenses;
    } catch (e) {
      throw Exception('Failed to fetch expenses for range: $e');
    }
  }

  /// Every transaction that moves [accountId]'s balance — paid from it, paid
  /// into it, or a transfer out of or into it — newest first, across all
  /// years. Powers the account statement, which needs the full history for
  /// its running balance to start from the opening balance.
  Future<List<Expense>> getExpensesForAccount(int accountId) async {
    final db = await database;
    final maps = await db.query(
      DbConstants.tableExpenses,
      where: '${DbConstants.colAccountId} = ? OR '
          '(${DbConstants.colType} = ? AND ${DbConstants.colToAccountId} = ?)',
      whereArgs: [accountId, DbConstants.txTransfer, accountId],
      orderBy: '${DbConstants.colDate} DESC',
    );
    return [for (final m in maps) Expense.fromMap(m)];
  }

  Future<int> updateExpense(Expense expense) async {
    final db = await database;
    try {
      return await db.update(DbConstants.tableExpenses, expense.toMap(),
          where: '${DbConstants.colId} = ?', whereArgs: [expense.id]);
    } catch (e) {
      throw Exception('Failed to update expense: $e');
    }
  }

  Future<int> deleteExpense(int id) async {
    final db = await database;
    try {
      return await db.delete(DbConstants.tableExpenses,
          where: '${DbConstants.colId} = ?', whereArgs: [id]);
    } catch (e) {
      throw Exception('Failed to delete expense: $e');
    }
  }

  /// Deletes every row in [ids] in one transaction (the Transactions tab's
  /// bulk delete). Returns how many were removed.
  Future<int> deleteExpenses(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return 0;
    final db = await database;
    return db.transaction((txn) async {
      var deleted = 0;
      for (final chunk in _chunks(list)) {
        deleted += await txn.delete(DbConstants.tableExpenses,
            where: '${DbConstants.colId} IN (${_placeholders(chunk.length)})',
            whereArgs: chunk);
      }
      return deleted;
    });
  }

  /// SQLite builds before 3.32 cap a statement at 999 bound values, so bulk
  /// `IN (...)` lists (select-all on a large year) are split into chunks.
  static const _maxInListArgs = 500;

  static Iterable<List<int>> _chunks(List<int> ids) sync* {
    for (var i = 0; i < ids.length; i += _maxInListArgs) {
      yield ids.sublist(i, min(i + _maxInListArgs, ids.length));
    }
  }

  static String _placeholders(int n) => List.filled(n, '?').join(',');

  /// Files every row in [ids] under [category] in one statement (bulk
  /// recategorise). Transfers are skipped: their category is fixed. Returns
  /// how many rows changed.
  Future<int> setCategory(Iterable<int> ids, String category) async {
    final list = ids.toList();
    if (list.isEmpty || category.trim().isEmpty) return 0;
    final db = await database;
    return db.transaction((txn) async {
      var changed = 0;
      for (final chunk in _chunks(list)) {
        changed += await txn.update(
          DbConstants.tableExpenses,
          {DbConstants.colCategory: category.trim()},
          where: '${DbConstants.colId} IN (${_placeholders(chunk.length)}) '
              'AND ${DbConstants.colType} != ?',
          whereArgs: [...chunk, DbConstants.txTransfer],
        );
      }
      return changed;
    });
  }

  Future<void> clearExpenses() async {
    final db = await database;
    await db.delete(DbConstants.tableExpenses);
  }

  /// Years of the earliest and latest transactions, or null when there are
  /// none. Drives the year filter so old data stays reachable.
  Future<(int, int)?> transactionYearBounds() async {
    final db = await database;
    final row = (await db.rawQuery('SELECT MIN(${DbConstants.colDate}) AS lo, '
            'MAX(${DbConstants.colDate}) AS hi '
            'FROM ${DbConstants.tableExpenses}'))
        .first;
    final lo = row['lo'] as String?;
    final hi = row['hi'] as String?;
    if (lo == null || hi == null) return null;
    return (DateTime.parse(lo).year, DateTime.parse(hi).year);
  }

  /// Returns categories used most often in the last [days] days for the
  /// given transaction [type], most-frequent first.
  Future<List<String>> frequentCategories(String type,
      {int days = 90, int limit = 6}) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(Duration(days: days)).toIso8601String();
    final maps = await db.rawQuery(
      'SELECT ${DbConstants.colCategory} AS category, COUNT(*) AS n '
      'FROM ${DbConstants.tableExpenses} '
      'WHERE ${DbConstants.colType} = ? AND ${DbConstants.colDate} >= ? '
      'AND ${DbConstants.colCategory} IS NOT NULL '
      'AND ${DbConstants.colCategory} != "" '
      'GROUP BY ${DbConstants.colCategory} '
      'ORDER BY n DESC LIMIT ?',
      [type, cutoff, limit],
    );
    return maps.map((m) => m['category'] as String).toList();
  }

  /// Every category used on [type] rows (expense or income) with how many
  /// transactions carry it, most-used first. Spellings are kept as stored, so
  /// "Food" and "food " show up separately — which is what the categories
  /// screen needs to offer merging them.
  Future<List<({String category, int count})>> categoryUsage(
      String type) async {
    final db = await database;
    final maps = await db.rawQuery(
      'SELECT ${DbConstants.colCategory} AS category, COUNT(*) AS n '
      'FROM ${DbConstants.tableExpenses} '
      'WHERE ${DbConstants.colType} = ? '
      'AND ${DbConstants.colCategory} IS NOT NULL '
      "AND trim(${DbConstants.colCategory}) != '' "
      'GROUP BY ${DbConstants.colCategory} '
      'ORDER BY n DESC, ${DbConstants.colCategory} COLLATE NOCASE',
      [type],
    );
    return [
      for (final m in maps)
        (category: m['category'] as String, count: (m['n'] as num).toInt()),
    ];
  }

  /// Renames category [from] to [to] on every [type] row (expense or income),
  /// merging it into [to] when that category already exists. Returns the
  /// number of transactions moved.
  ///
  /// [from] matches ignoring case and surrounding spaces, the same leniency
  /// budgets use, so every spelling of it moves together. Recurring rules and
  /// quick-add templates of the same type move too, or they would recreate the
  /// old category the next time they post. For expenses, budgets follow: a
  /// month where both categories had a cap ends with one cap of their sum,
  /// rather than two caps the budgets screen would resolve arbitrarily.
  /// Merchant category memory needs no update; it is derived from these rows.
  Future<int> renameCategory(String from, String to,
      {required String type}) async {
    final target = to.trim();
    if (target.isEmpty || from == target) return 0;
    final db = await database;
    const matches = 'lower(trim(${DbConstants.colCategory})) = lower(trim(?))';
    return db.transaction((txn) async {
      final moved = await txn.update(
        DbConstants.tableExpenses,
        {DbConstants.colCategory: target},
        where: '${DbConstants.colType} = ? AND $matches',
        whereArgs: [type, from],
      );
      await txn.update(
        DbConstants.tableRecurringRules,
        {DbConstants.colCategory: target},
        where: '${DbConstants.colType} = ? '
            'AND ${DbConstants.colIsInvestment} = 0 AND $matches',
        whereArgs: [type, from],
      );
      await txn.update(
        DbConstants.tableTemplates,
        {DbConstants.colCategory: target},
        where: '${DbConstants.colType} = ? AND $matches',
        whereArgs: [type, from],
      );
      if (type == DbConstants.txExpense &&
          normalizeCategory(from) !=
              normalizeCategory(Budget.overallCategory)) {
        final sources = await txn.query(DbConstants.tableBudgets,
            columns: [DbConstants.colId], where: matches, whereArgs: [from]);
        for (final source in sources) {
          // Re-read each row: an earlier iteration may have merged into it
          // (several spellings of [from] in one month) or deleted it.
          final current = await txn.query(DbConstants.tableBudgets,
              where: '${DbConstants.colId} = ?',
              whereArgs: [source[DbConstants.colId]]);
          if (current.isEmpty) continue;
          final b = Budget.fromMap(current.first);
          final existing = await txn.query(
            DbConstants.tableBudgets,
            where: '${DbConstants.colId} != ? AND ${DbConstants.colYear} = ? '
                'AND ${DbConstants.colMonth} = ? AND $matches',
            whereArgs: [b.id, b.year, b.month, target],
            limit: 1,
          );
          if (existing.isEmpty) {
            await txn.update(
                DbConstants.tableBudgets, {DbConstants.colCategory: target},
                where: '${DbConstants.colId} = ?', whereArgs: [b.id]);
          } else {
            final other = Budget.fromMap(existing.first);
            await txn.update(
                DbConstants.tableBudgets,
                {
                  DbConstants.colCategory: target,
                  DbConstants.colAmount: other.amount + b.amount,
                },
                where: '${DbConstants.colId} = ?',
                whereArgs: [other.id]);
            await txn.delete(DbConstants.tableBudgets,
                where: '${DbConstants.colId} = ?', whereArgs: [b.id]);
          }
        }
      }
      return moved;
    });
  }

  /// Every receipt photo a transaction still refers to.
  Future<Set<String>> referencedAttachments() async {
    final db = await database;
    final rows =
        await db.rawQuery('SELECT DISTINCT ${DbConstants.colAttachment} AS a '
            'FROM ${DbConstants.tableExpenses} '
            'WHERE ${DbConstants.colAttachment} IS NOT NULL');
    return {for (final r in rows) r['a'] as String};
  }

  /// How often each merchant has been filed under each category, most-used
  /// first and newest first within a tie.
  ///
  /// Feeds [CategoryMemory], which pre-fills the category of an imported
  /// transaction from what the same merchant was filed under before.
  /// Transfers are excluded — their category is fixed and carries no signal.
  Future<List<Map<String, Object?>>> merchantCategoryCounts(
      {int limit = 500}) async {
    final db = await database;
    return db.rawQuery(
      'SELECT ${DbConstants.colDescription}, ${DbConstants.colCategory}, '
      'COUNT(*) AS n, MAX(${DbConstants.colDate}) AS lastDate '
      'FROM ${DbConstants.tableExpenses} '
      'WHERE ${DbConstants.colType} != ? '
      'AND ${DbConstants.colDescription} IS NOT NULL '
      "AND ${DbConstants.colDescription} != '' "
      'AND ${DbConstants.colCategory} IS NOT NULL '
      "AND ${DbConstants.colCategory} != '' "
      'GROUP BY ${DbConstants.colDescription}, ${DbConstants.colCategory} '
      'ORDER BY n DESC, lastDate DESC LIMIT ?',
      [DbConstants.txTransfer, limit],
    );
  }
}
