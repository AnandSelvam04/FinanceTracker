import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import '../models/account.dart';
import '../models/expense.dart';
import '../models/investment.dart';
import '../models/budget.dart';
import '../models/net_worth_point.dart';
import '../models/recurring_rule.dart';
import '../models/tx_template.dart';
import '../utils/app_logger.dart';
import '../utils/db_constants.dart';

class DBService {
  static final DBService _instance = DBService._internal();
  factory DBService() => _instance;
  DBService._internal();

  /// Test-only hook so tests can point the singleton at an isolated file.
  static String? dbNameOverride;

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const _kEncEnabledFlag = 'db_encryption_enabled';
  static const _kEncKey = 'db_encryption_key';

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  /// Closes the database so the next access re-opens it (used by the
  /// encryption migration to switch the file's cipher state).
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Whether the on-device database is currently encrypted. Always false in
  /// test mode. Never throws (returns false if secure storage is unavailable).
  Future<bool> isEncryptionEnabled() async {
    if (testFactory != null || dbNameOverride != null) return false;
    try {
      return (await _secureStorage.read(key: _kEncEnabledFlag)) == 'true';
    } catch (_) {
      return false;
    }
  }

  /// Password to open the database: the stored key when encryption is on,
  /// otherwise null (plaintext). Guarded so the plain path never fails on a
  /// host without secure storage (unit tests, desktop).
  Future<String?> _password() async {
    if (dbNameOverride != null) return null;
    try {
      if ((await _secureStorage.read(key: _kEncEnabledFlag)) != 'true') {
        return null;
      }
      return await _getOrCreateKey();
    } catch (_) {
      return null;
    }
  }

  Future<String> _getOrCreateKey() async {
    var key = await _secureStorage.read(key: _kEncKey);
    if (key == null || key.isEmpty) {
      final rnd = Random.secure();
      key = base64Url.encode(List<int>.generate(32, (_) => rnd.nextInt(256)));
      await _secureStorage.write(key: _kEncKey, value: key);
    }
    return key;
  }

  /// A [DatabaseFactory] injected by tests so the suite runs on
  /// sqflite_common_ffi. Production leaves this null and uses the SQLCipher
  /// factory (with the encryption password) directly. Necessary because
  /// sqflite_sqlcipher's top-level functions hit the native method channel and
  /// ignore the ffi factory tests install globally.
  static DatabaseFactory? testFactory;

  Future<Database> _initDB() async {
    final factory = testFactory;
    if (factory != null) {
      // Test path: plaintext, driven by the injected ffi factory.
      final path = join(await factory.getDatabasesPath(),
          dbNameOverride ?? DbConstants.dbName);
      return factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: DbConstants.dbVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
    }
    // Production path: SQLCipher; encrypted when the user has opted in.
    final path = join(await getDatabasesPath(), DbConstants.dbName);
    return openDatabase(
      path,
      password: await _password(),
      version: DbConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
          CREATE TABLE ${DbConstants.tableExpenses}(
            ${DbConstants.colId} INTEGER PRIMARY KEY AUTOINCREMENT,
            ${DbConstants.colDescription} TEXT,
            ${DbConstants.colAmount} REAL,
            ${DbConstants.colDate} TEXT,
            ${DbConstants.colCategory} TEXT,
            ${DbConstants.colPaymentMode} TEXT,
            ${DbConstants.colType} TEXT NOT NULL DEFAULT '${DbConstants.txExpense}',
            ${DbConstants.colAccountId} INTEGER,
            ${DbConstants.colToAccountId} INTEGER
          )
        ''');
    await db.execute('''
          CREATE TABLE ${DbConstants.tableInvestments}(
            ${DbConstants.colId} INTEGER PRIMARY KEY AUTOINCREMENT,
            ${DbConstants.colName} TEXT,
            ${DbConstants.colAmount} REAL,
            ${DbConstants.colDate} TEXT,
            ${DbConstants.colType} TEXT
          )
        ''');
    await db.execute('''
          CREATE TABLE ${DbConstants.tableBudgets}(
            ${DbConstants.colId} INTEGER PRIMARY KEY AUTOINCREMENT,
            ${DbConstants.colCategory} TEXT,
            ${DbConstants.colAmount} REAL,
            ${DbConstants.colYear} INTEGER,
            ${DbConstants.colMonth} INTEGER
          )
        ''');
    await _createAccountsTable(db);
    await _createRecurringTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
          // Rename 'title' to 'description' in expenses table
          await db.execute('ALTER TABLE ${DbConstants.tableExpenses} RENAME TO expenses_old;');
          await db.execute('''
            CREATE TABLE ${DbConstants.tableExpenses}(
              ${DbConstants.colId} INTEGER PRIMARY KEY AUTOINCREMENT,
              ${DbConstants.colDescription} TEXT,
              ${DbConstants.colAmount} REAL,
              ${DbConstants.colDate} TEXT,
              ${DbConstants.colCategory} TEXT,
              ${DbConstants.colPaymentMode} TEXT
            )
          ''');
          // Copy data from old table to new table
          await db.execute('''
            INSERT INTO ${DbConstants.tableExpenses} (${DbConstants.colId}, ${DbConstants.colDescription}, ${DbConstants.colAmount}, ${DbConstants.colDate}, ${DbConstants.colCategory}, ${DbConstants.colPaymentMode})
            SELECT id, title as description, amount, date, category, paymentMode FROM expenses_old;
          ''');
          await db.execute('DROP TABLE expenses_old;');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE ${DbConstants.tableBudgets}(
              ${DbConstants.colId} INTEGER PRIMARY KEY AUTOINCREMENT,
              ${DbConstants.colCategory} TEXT,
              ${DbConstants.colAmount} REAL,
              ${DbConstants.colYear} INTEGER,
              ${DbConstants.colMonth} INTEGER
            )
          ''');
        }
        if (oldVersion < 4) {
          await _createAccountsTable(db);
          await db.execute(
              "ALTER TABLE ${DbConstants.tableExpenses} ADD COLUMN ${DbConstants.colType} TEXT NOT NULL DEFAULT '${DbConstants.txExpense}'");
          await db.execute(
              'ALTER TABLE ${DbConstants.tableExpenses} ADD COLUMN ${DbConstants.colAccountId} INTEGER');
          await db.execute(
              'ALTER TABLE ${DbConstants.tableExpenses} ADD COLUMN ${DbConstants.colToAccountId} INTEGER');
        }
        if (oldVersion < 5) {
          await _createRecurringTables(db);
        }
        if (oldVersion < 6) {
          // Convert all amounts from major-unit reals to integer minor units
          // (paise/cents) to eliminate floating-point rounding.
          await db.execute(
              'UPDATE ${DbConstants.tableExpenses} SET ${DbConstants.colAmount} = CAST(ROUND(${DbConstants.colAmount} * 100) AS INTEGER)');
          await db.execute(
              'UPDATE ${DbConstants.tableInvestments} SET ${DbConstants.colAmount} = CAST(ROUND(${DbConstants.colAmount} * 100) AS INTEGER)');
          await db.execute(
              'UPDATE ${DbConstants.tableBudgets} SET ${DbConstants.colAmount} = CAST(ROUND(${DbConstants.colAmount} * 100) AS INTEGER)');
          await db.execute(
              'UPDATE ${DbConstants.tableAccounts} SET ${DbConstants.colOpeningBalance} = CAST(ROUND(${DbConstants.colOpeningBalance} * 100) AS INTEGER)');
          await db.execute(
              'UPDATE ${DbConstants.tableRecurringRules} SET ${DbConstants.colAmount} = CAST(ROUND(${DbConstants.colAmount} * 100) AS INTEGER)');
          await db.execute(
              'UPDATE ${DbConstants.tableTemplates} SET ${DbConstants.colAmount} = CAST(ROUND(${DbConstants.colAmount} * 100) AS INTEGER)');
        }
        if (oldVersion >= 4 && oldVersion < 7) {
          // Per-account currency + exchange rate. Only devices whose accounts
          // table predates this (oldVersion >= 4) need the columns added;
          // upgrades from < 4 already get them from _createAccountsTable.
          await db.execute(
              'ALTER TABLE ${DbConstants.tableAccounts} ADD COLUMN ${DbConstants.colCurrency} TEXT');
          await db.execute(
              'ALTER TABLE ${DbConstants.tableAccounts} ADD COLUMN ${DbConstants.colRate} REAL NOT NULL DEFAULT 1');
        }
  }

  static Future<void> _createAccountsTable(Database db) async {
    await db.execute('''
      CREATE TABLE ${DbConstants.tableAccounts}(
        ${DbConstants.colId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colName} TEXT NOT NULL,
        ${DbConstants.colType} TEXT NOT NULL,
        ${DbConstants.colOpeningBalance} REAL NOT NULL DEFAULT 0,
        ${DbConstants.colColor} INTEGER,
        ${DbConstants.colCurrency} TEXT,
        ${DbConstants.colRate} REAL NOT NULL DEFAULT 1
      )
    ''');
  }

  static Future<void> _createRecurringTables(Database db) async {
    await db.execute('''
      CREATE TABLE ${DbConstants.tableRecurringRules}(
        ${DbConstants.colId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colDescription} TEXT,
        ${DbConstants.colAmount} REAL,
        ${DbConstants.colCategory} TEXT,
        ${DbConstants.colType} TEXT NOT NULL DEFAULT '${DbConstants.txExpense}',
        ${DbConstants.colAccountId} INTEGER,
        ${DbConstants.colFrequency} TEXT NOT NULL,
        ${DbConstants.colNextDue} TEXT NOT NULL,
        ${DbConstants.colAnchorDay} INTEGER NOT NULL DEFAULT 1,
        ${DbConstants.colEnabled} INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE ${DbConstants.tableTemplates}(
        ${DbConstants.colId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colName} TEXT NOT NULL,
        ${DbConstants.colDescription} TEXT,
        ${DbConstants.colAmount} REAL,
        ${DbConstants.colCategory} TEXT,
        ${DbConstants.colType} TEXT NOT NULL DEFAULT '${DbConstants.txExpense}',
        ${DbConstants.colAccountId} INTEGER
      )
    ''');
  }

  // Expense CRUD
  Future<int> insertExpense(Expense expense) async {
    final db = await database;
    try {
      return await db.insert(DbConstants.tableExpenses, expense.toMap());
    } catch (e) {
      throw Exception('Failed to insert expense: $e');
    }
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

  Future<void> clearExpenses() async {
    final db = await database;
    await db.delete(DbConstants.tableExpenses);
  }

  // Investment CRUD
  Future<int> insertInvestment(Investment investment) async {
    final db = await database;
    return await db.insert(DbConstants.tableInvestments, investment.toMap());
  }

  Future<List<Investment>> getInvestments() async {
    final db = await database;
    final maps = await db.query(DbConstants.tableInvestments, orderBy: '${DbConstants.colDate} DESC');
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
    return await db.delete(DbConstants.tableInvestments, where: '${DbConstants.colId} = ?', whereArgs: [id]);
  }

  Future<void> clearInvestments() async {
    final db = await database;
    await db.delete(DbConstants.tableInvestments);
  }

  Future<void> clearAll() async {
    await clearExpenses();
    await clearInvestments();
    await clearBudgets();
    await clearAccounts();
    await clearRecurringRules();
    await clearTemplates();
  }

  // --- At-rest encryption (opt-in) -----------------------------------------

  static const List<String> _allTables = [
    DbConstants.tableAccounts,
    DbConstants.tableExpenses,
    DbConstants.tableInvestments,
    DbConstants.tableBudgets,
    DbConstants.tableRecurringRules,
    DbConstants.tableTemplates,
  ];

  Future<Map<String, List<Map<String, Object?>>>> _dumpAllTables(
      Database db) async {
    final out = <String, List<Map<String, Object?>>>{};
    for (final t in _allTables) {
      out[t] = await db.query(t);
    }
    return out;
  }

  Future<void> _restoreAllTables(
      Database db, Map<String, List<Map<String, Object?>>> data) async {
    final batch = db.batch();
    for (final t in _allTables) {
      for (final row in data[t] ?? const []) {
        batch.insert(t, row);
      }
    }
    await batch.commit(noResult: true);
  }

  bool _sameCounts(Map<String, List<Object?>> a, Map<String, List<Object?>> b) {
    for (final t in _allTables) {
      if ((a[t]?.length ?? 0) != (b[t]?.length ?? 0)) return false;
    }
    return true;
  }

  Future<void> _writeSafetySnapshot(
      Map<String, List<Map<String, Object?>>> data) async {
    final path = join(await getDatabasesPath(), 'finance_pre_migration.json');
    await File(path).writeAsString(jsonEncode(data));
  }

  /// Test hook exercising the table dump→restore copy used by the migration,
  /// so the copy logic is covered without real encryption/secure storage.
  Future<void> debugRoundTripTables() async {
    final db = await database;
    final snapshot = await _dumpAllTables(db);
    await clearAll();
    await _restoreAllTables(db, snapshot);
  }

  /// Encrypts the on-device database in place. Safe by construction: writes a
  /// JSON safety snapshot, copies all rows into a fresh encrypted database,
  /// verifies row counts, and rolls back to plaintext on any failure so data
  /// is never lost.
  Future<void> enableEncryption() async {
    if (testFactory != null || dbNameOverride != null) {
      throw Exception('Encryption is not available in test mode');
    }
    if (await isEncryptionEnabled()) return;
    final snapshot = await _dumpAllTables(await database);
    await _writeSafetySnapshot(snapshot);
    final path = join(await getDatabasesPath(), DbConstants.dbName);
    await close();
    await deleteDatabase(path);
    await _getOrCreateKey();
    await _secureStorage.write(key: _kEncEnabledFlag, value: 'true');
    try {
      final enc = await database; // reopens encrypted via _password()
      await _restoreAllTables(enc, snapshot);
      if (!_sameCounts(snapshot, await _dumpAllTables(enc))) {
        throw Exception('Row-count verification failed after encryption');
      }
    } catch (e) {
      // Roll back to plaintext — no data loss.
      await _secureStorage.write(key: _kEncEnabledFlag, value: 'false');
      await close();
      await deleteDatabase(path);
      await _restoreAllTables(await database, snapshot);
      rethrow;
    }
  }

  /// Reverses [enableEncryption], returning the database to plaintext with the
  /// same verify-and-rollback safety.
  Future<void> disableEncryption() async {
    if (testFactory != null || dbNameOverride != null) {
      throw Exception('Encryption is not available in test mode');
    }
    if (!await isEncryptionEnabled()) return;
    final snapshot = await _dumpAllTables(await database);
    await _writeSafetySnapshot(snapshot);
    final path = join(await getDatabasesPath(), DbConstants.dbName);
    await close();
    await deleteDatabase(path);
    await _secureStorage.write(key: _kEncEnabledFlag, value: 'false');
    try {
      final plain = await database; // reopens plaintext
      await _restoreAllTables(plain, snapshot);
      if (!_sameCounts(snapshot, await _dumpAllTables(plain))) {
        throw Exception('Row-count verification failed after decryption');
      }
    } catch (e) {
      await _secureStorage.write(key: _kEncEnabledFlag, value: 'true');
      await close();
      await deleteDatabase(path);
      await _restoreAllTables(await database, snapshot);
      rethrow;
    }
  }

  /// Returns categories used most often in the last [days] days for the
  /// given transaction [type], most-frequent first.
  Future<List<String>> frequentCategories(String type,
      {int days = 90, int limit = 6}) async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String();
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

  // Budget CRUD
  Future<int> insertBudget(Budget budget) async {
    final db = await database;
    return await db.insert(DbConstants.tableBudgets, budget.toMap());
  }

  Future<List<Budget>> getBudgets() async {
    final db = await database;
    final maps = await db.query(DbConstants.tableBudgets);
    return maps.map((map) => Budget.fromMap(map)).toList();
  }

  Future<int> updateBudget(Budget budget) async {
    final db = await database;
    return await db.update(DbConstants.tableBudgets, budget.toMap(),
        where: '${DbConstants.colId} = ?', whereArgs: [budget.id]);
  }

  Future<int> deleteBudget(int id) async {
    final db = await database;
    return await db.delete(DbConstants.tableBudgets, where: '${DbConstants.colId} = ?', whereArgs: [id]);
  }

  Future<void> clearBudgets() async {
    final db = await database;
    await db.delete(DbConstants.tableBudgets);
  }

  // Account CRUD
  Future<int> insertAccount(Account account) async {
    final db = await database;
    return await db.insert(DbConstants.tableAccounts, account.toMap());
  }

  Future<List<Account>> getAccounts() async {
    final db = await database;
    final maps =
        await db.query(DbConstants.tableAccounts, orderBy: DbConstants.colName);
    return maps.map((map) => Account.fromMap(map)).toList();
  }

  Future<int> updateAccount(Account account) async {
    final db = await database;
    return await db.update(DbConstants.tableAccounts, account.toMap(),
        where: '${DbConstants.colId} = ?', whereArgs: [account.id]);
  }

  Future<int> deleteAccount(int id) async {
    final db = await database;
    // Detach the account from any transactions so they don't keep a
    // dangling reference to a deleted account.
    await db.update(
      DbConstants.tableExpenses,
      {DbConstants.colAccountId: null},
      where: '${DbConstants.colAccountId} = ?',
      whereArgs: [id],
    );
    await db.update(
      DbConstants.tableExpenses,
      {DbConstants.colToAccountId: null},
      where: '${DbConstants.colToAccountId} = ?',
      whereArgs: [id],
    );
    return await db.delete(DbConstants.tableAccounts,
        where: '${DbConstants.colId} = ?', whereArgs: [id]);
  }

  Future<void> clearAccounts() async {
    final db = await database;
    await db.delete(DbConstants.tableAccounts);
  }

  // Recurring rule CRUD
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

  // Template CRUD
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

  /// Net worth (minor units) at the end of each of the last [months] months,
  /// oldest first. Net worth = account opening balances + cumulative
  /// (income − expense) + cumulative investments, as of each month end.
  /// Transfers are account-to-account and cancel out, so they are ignored.
  Future<List<NetWorthPoint>> netWorthSeries(int months,
      {DateTime? now}) async {
    final db = await database;
    final today = now ?? DateTime.now();

    final openingRow = await db.rawQuery(
        'SELECT SUM(${DbConstants.colOpeningBalance}) AS total '
        'FROM ${DbConstants.tableAccounts}');
    final opening = ((openingRow.first['total'] ?? 0) as num).round();

    Future<int> sumBefore(String table, DateTime cutoff, {String? type}) async {
      final where = StringBuffer('${DbConstants.colDate} < ?');
      final args = <Object?>[cutoff.toIso8601String()];
      if (type != null) {
        where.write(' AND ${DbConstants.colType} = ?');
        args.add(type);
      }
      final row = await db.rawQuery(
        'SELECT SUM(${DbConstants.colAmount}) AS total FROM $table WHERE $where',
        args,
      );
      return ((row.first['total'] ?? 0) as num).round();
    }

    final series = <NetWorthPoint>[];
    for (int i = months - 1; i >= 0; i--) {
      final monthStart = DateTime(today.year, today.month - i, 1);
      // First day of the following month = exclusive cutoff (month end).
      final cutoff = DateTime(today.year, today.month - i + 1, 1);
      final income = await sumBefore(DbConstants.tableExpenses, cutoff,
          type: DbConstants.txIncome);
      final expense = await sumBefore(DbConstants.tableExpenses, cutoff,
          type: DbConstants.txExpense);
      final investments = await sumBefore(DbConstants.tableInvestments, cutoff);
      series.add(NetWorthPoint(
        month: monthStart,
        value: opening + income - expense + investments,
      ));
    }
    return series;
  }

  /// Balance = opening + income − expenses − outgoing transfers
  /// + incoming transfers. Computed in SQL so it covers all years,
  /// not just those loaded into ExpenseProvider.
  Future<int> getAccountBalance(Account account) async {
    final db = await database;

    Future<int> sumWhere(String where, List<Object?> args) async {
      final result = await db.rawQuery(
        'SELECT SUM(${DbConstants.colAmount}) AS total FROM ${DbConstants.tableExpenses} WHERE $where',
        args,
      );
      return ((result.first['total'] ?? 0) as num).round();
    }

    final income = await sumWhere(
        '${DbConstants.colType} = ? AND ${DbConstants.colAccountId} = ?',
        [DbConstants.txIncome, account.id]);
    final spent = await sumWhere(
        '${DbConstants.colType} = ? AND ${DbConstants.colAccountId} = ?',
        [DbConstants.txExpense, account.id]);
    final transferredOut = await sumWhere(
        '${DbConstants.colType} = ? AND ${DbConstants.colAccountId} = ?',
        [DbConstants.txTransfer, account.id]);
    final transferredIn = await sumWhere(
        '${DbConstants.colType} = ? AND ${DbConstants.colToAccountId} = ?',
        [DbConstants.txTransfer, account.id]);

    return account.openingBalance +
        income -
        spent -
        transferredOut +
        transferredIn;
  }
}
