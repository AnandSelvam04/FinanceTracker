import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import '../models/account.dart';
import '../models/expense.dart';
import '../models/goal.dart';
import '../models/investment.dart';
import '../models/budget.dart';
import '../models/net_worth_point.dart';
import '../models/recurring_rule.dart';
import '../models/tx_template.dart';
import '../utils/app_logger.dart';
import '../utils/currency_format.dart';
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
  /// test mode.
  ///
  /// A secure-storage read can fail transiently (keystore not yet unlocked
  /// after boot, for one). Treating that as "encryption is off" is a lie that
  /// used to propagate silently: Settings showed the toggle off, and the
  /// backup paths wrote plaintext. It still reports false so the UI has
  /// something to render, but the failure is logged and
  /// [readEncryptionFlagOrThrow] gives the paths that must not guess a way to
  /// tell the two apart.
  Future<bool> isEncryptionEnabled() async {
    if (testFactory != null || dbNameOverride != null) return false;
    try {
      return await readEncryptionFlagOrThrow();
    } catch (e) {
      AppLogger.error(
          'Could not read the encryption flag from secure storage; '
          'reporting encryption as off',
          e);
      return false;
    }
  }

  /// Reads the encryption flag, propagating a secure-storage failure instead
  /// of collapsing it into `false`.
  Future<bool> readEncryptionFlagOrThrow() async {
    if (testFactory != null || dbNameOverride != null) return false;
    return (await _secureStorage.read(key: _kEncEnabledFlag)) == 'true';
  }

  /// Password to open the database: the stored key when encryption is on,
  /// otherwise null (plaintext).
  ///
  /// Only the *flag read* is guarded, so the plain path still works on a host
  /// without secure storage (unit tests, desktop). Once we know encryption is
  /// on, a failure to fetch the key is fatal and propagates — returning null
  /// there would try to open an encrypted file with no key and surface as an
  /// unintelligible SQLite error.
  Future<String?> _password() async {
    if (dbNameOverride != null) return null;
    bool enabled;
    try {
      enabled = await readEncryptionFlagOrThrow();
    } catch (e) {
      AppLogger.error(
          'Secure storage unavailable; opening the database unencrypted', e);
      return null;
    }
    return enabled ? await _getOrCreateKey() : null;
  }

  /// The device-held database key when at-rest encryption is on, otherwise
  /// null. Used to protect the automatic local backup with the same key, so
  /// enabling DB encryption doesn't leave a readable JSON copy on disk.
  ///
  /// Throws if encryption is on but the key can't be read: callers use this to
  /// decide whether to encrypt a backup, and a null there would quietly write
  /// the plaintext copy this exists to prevent.
  Future<String?> deviceKeyIfEncrypted() async {
    if (!await readEncryptionFlagOrThrow()) return null;
    return _getOrCreateKey();
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
            ${DbConstants.colAmount} INTEGER,
            ${DbConstants.colDate} TEXT,
            ${DbConstants.colCategory} TEXT,
            ${DbConstants.colPaymentMode} TEXT,
            ${DbConstants.colType} TEXT NOT NULL DEFAULT '${DbConstants.txExpense}',
            ${DbConstants.colAccountId} INTEGER,
            ${DbConstants.colToAccountId} INTEGER,
            ${DbConstants.colToAmount} INTEGER,
            ${DbConstants.colSourceRef} TEXT
          )
        ''');
    await _createExpenseIndexes(db);
    await _createSourceRefIndex(db);
    await _createSmsIgnoredTable(db);
    await db.execute('''
          CREATE TABLE ${DbConstants.tableInvestments}(
            ${DbConstants.colId} INTEGER PRIMARY KEY AUTOINCREMENT,
            ${DbConstants.colName} TEXT,
            ${DbConstants.colAmount} INTEGER,
            ${DbConstants.colDate} TEXT,
            ${DbConstants.colType} TEXT
          )
        ''');
    await db.execute('''
          CREATE TABLE ${DbConstants.tableBudgets}(
            ${DbConstants.colId} INTEGER PRIMARY KEY AUTOINCREMENT,
            ${DbConstants.colCategory} TEXT,
            ${DbConstants.colAmount} INTEGER,
            ${DbConstants.colYear} INTEGER,
            ${DbConstants.colMonth} INTEGER
          )
        ''');
    await _createAccountsTable(db);
    await _createRecurringTables(db);
    await _createGoalsTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Rename 'title' to 'description' in expenses table
      await db.execute(
          'ALTER TABLE ${DbConstants.tableExpenses} RENAME TO expenses_old;');
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
    if (oldVersion < 8) {
      // Destination-side amount for cross-currency transfers (null means
      // both sides move by `amount`), plus indexes for the date-range,
      // balance, and net-worth queries.
      await db.execute(
          'ALTER TABLE ${DbConstants.tableExpenses} ADD COLUMN ${DbConstants.colToAmount} INTEGER');
      await _createExpenseIndexes(db);
    }
    if (oldVersion < 9) {
      await _migrateAmountsToInteger(db);
    }
    if (oldVersion < 10) {
      // SMS import: a dedup key on transactions, the last-4 that routes a
      // message to an account, and the dismissal list for the review queue.
      await db.execute(
          'ALTER TABLE ${DbConstants.tableExpenses} ADD COLUMN ${DbConstants.colSourceRef} TEXT');
      await db.execute(
          'ALTER TABLE ${DbConstants.tableAccounts} ADD COLUMN ${DbConstants.colLast4} TEXT');
      await _createSourceRefIndex(db);
      await _createSmsIgnoredTable(db);
    }
    if (oldVersion < 11) {
      // Savings goals.
      await _createGoalsTable(db);
    }
  }

  /// v9: give every money column INTEGER affinity.
  ///
  /// Amounts became integer minor units back in v6, but the columns were still
  /// declared REAL, so SQLite coerced each one to a double on write and the
  /// Dart side rounded it back on read. It worked, yet it quietly gave up the
  /// exactness the minor-unit migration existed to provide — and `SUM()` came
  /// back as a float. Only whole numbers are stored, so the values themselves
  /// do not change.
  ///
  /// SQLite cannot alter a column's type, so each table is rebuilt. sqflite
  /// runs onUpgrade inside a transaction, so a failure here rolls the whole
  /// thing back rather than leaving half-converted tables.
  static Future<void> _migrateAmountsToInteger(Database db) async {
    // (table, column definitions, columns to copy) — amount columns are
    // CAST on the way across; everything else is copied verbatim.
    Future<void> rebuild(
        String table, String columns, List<String> copy) async {
      // Databases upgrading from an old enough version may not have every
      // table yet (the earlier migration steps create some of them), so a
      // missing table here is normal rather than an error.
      final exists = await db.rawQuery(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
          [table]);
      if (exists.isEmpty) return;

      final tmp = '${table}_v9';
      await db.execute('CREATE TABLE $tmp($columns)');
      final names = copy.join(', ');
      await db.execute('INSERT INTO $tmp ($names) SELECT $names FROM $table');
      await db.execute('DROP TABLE $table');
      await db.execute('ALTER TABLE $tmp RENAME TO $table');
    }

    const amt = DbConstants.colAmount;
    final id = DbConstants.colId;

    await rebuild(
      DbConstants.tableExpenses,
      '''
        $id INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colDescription} TEXT,
        $amt INTEGER,
        ${DbConstants.colDate} TEXT,
        ${DbConstants.colCategory} TEXT,
        ${DbConstants.colPaymentMode} TEXT,
        ${DbConstants.colType} TEXT NOT NULL DEFAULT '${DbConstants.txExpense}',
        ${DbConstants.colAccountId} INTEGER,
        ${DbConstants.colToAccountId} INTEGER,
        ${DbConstants.colToAmount} INTEGER
      ''',
      [
        id,
        DbConstants.colDescription,
        amt,
        DbConstants.colDate,
        DbConstants.colCategory,
        DbConstants.colPaymentMode,
        DbConstants.colType,
        DbConstants.colAccountId,
        DbConstants.colToAccountId,
        DbConstants.colToAmount,
      ],
    );
    // Dropping the table dropped its indexes with it.
    await _createExpenseIndexes(db);

    await rebuild(
      DbConstants.tableInvestments,
      '''
        $id INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colName} TEXT,
        $amt INTEGER,
        ${DbConstants.colDate} TEXT,
        ${DbConstants.colType} TEXT
      ''',
      [id, DbConstants.colName, amt, DbConstants.colDate, DbConstants.colType],
    );

    await rebuild(
      DbConstants.tableBudgets,
      '''
        $id INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colCategory} TEXT,
        $amt INTEGER,
        ${DbConstants.colYear} INTEGER,
        ${DbConstants.colMonth} INTEGER
      ''',
      [
        id,
        DbConstants.colCategory,
        amt,
        DbConstants.colYear,
        DbConstants.colMonth
      ],
    );

    // `rate` stays REAL — it is a genuine fraction, not a money amount.
    await rebuild(
      DbConstants.tableAccounts,
      '''
        $id INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colName} TEXT NOT NULL,
        ${DbConstants.colType} TEXT NOT NULL,
        ${DbConstants.colOpeningBalance} INTEGER NOT NULL DEFAULT 0,
        ${DbConstants.colColor} INTEGER,
        ${DbConstants.colCurrency} TEXT,
        ${DbConstants.colRate} REAL NOT NULL DEFAULT 1
      ''',
      [
        id,
        DbConstants.colName,
        DbConstants.colType,
        DbConstants.colOpeningBalance,
        DbConstants.colColor,
        DbConstants.colCurrency,
        DbConstants.colRate,
      ],
    );

    await rebuild(
      DbConstants.tableRecurringRules,
      '''
        $id INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colDescription} TEXT,
        $amt INTEGER,
        ${DbConstants.colCategory} TEXT,
        ${DbConstants.colType} TEXT NOT NULL DEFAULT '${DbConstants.txExpense}',
        ${DbConstants.colAccountId} INTEGER,
        ${DbConstants.colFrequency} TEXT NOT NULL,
        ${DbConstants.colNextDue} TEXT NOT NULL,
        ${DbConstants.colAnchorDay} INTEGER NOT NULL DEFAULT 1,
        ${DbConstants.colEnabled} INTEGER NOT NULL DEFAULT 1
      ''',
      [
        id,
        DbConstants.colDescription,
        amt,
        DbConstants.colCategory,
        DbConstants.colType,
        DbConstants.colAccountId,
        DbConstants.colFrequency,
        DbConstants.colNextDue,
        DbConstants.colAnchorDay,
        DbConstants.colEnabled,
      ],
    );

    await rebuild(
      DbConstants.tableTemplates,
      '''
        $id INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colName} TEXT NOT NULL,
        ${DbConstants.colDescription} TEXT,
        $amt INTEGER,
        ${DbConstants.colCategory} TEXT,
        ${DbConstants.colType} TEXT NOT NULL DEFAULT '${DbConstants.txExpense}',
        ${DbConstants.colAccountId} INTEGER
      ''',
      [
        id,
        DbConstants.colName,
        DbConstants.colDescription,
        amt,
        DbConstants.colCategory,
        DbConstants.colType,
        DbConstants.colAccountId,
      ],
    );
  }

  static Future<void> _createExpenseIndexes(Database db) async {
    await db
        .execute('CREATE INDEX IF NOT EXISTS ${DbConstants.idxExpensesDate} '
            'ON ${DbConstants.tableExpenses}(${DbConstants.colDate})');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS ${DbConstants.idxExpensesTypeAccount} '
        'ON ${DbConstants.tableExpenses}(${DbConstants.colType}, ${DbConstants.colAccountId})');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS ${DbConstants.idxExpensesToAccount} '
        'ON ${DbConstants.tableExpenses}(${DbConstants.colToAccountId})');
  }

  /// Kept out of [_createExpenseIndexes] because that helper also runs during
  /// the v8 and v9 migrations, when the sourceRef column does not exist yet.
  ///
  /// Deliberately not UNIQUE: restore-without-clear merges a backup into the
  /// live database, and a unique constraint would abort the whole restore on
  /// any row the user already has. Duplicate suppression happens in
  /// [existingSourceRefs] instead, which is needed for the review queue
  /// regardless.
  static Future<void> _createSourceRefIndex(Database db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS ${DbConstants.idxExpensesSourceRef} '
        'ON ${DbConstants.tableExpenses}(${DbConstants.colSourceRef})');
  }

  static Future<void> _createSmsIgnoredTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbConstants.tableSmsIgnored}(
        ${DbConstants.colSourceRef} TEXT PRIMARY KEY
      )
    ''');
  }

  static Future<void> _createAccountsTable(Database db) async {
    await db.execute('''
      CREATE TABLE ${DbConstants.tableAccounts}(
        ${DbConstants.colId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colName} TEXT NOT NULL,
        ${DbConstants.colType} TEXT NOT NULL,
        ${DbConstants.colOpeningBalance} INTEGER NOT NULL DEFAULT 0,
        ${DbConstants.colColor} INTEGER,
        ${DbConstants.colCurrency} TEXT,
        ${DbConstants.colRate} REAL NOT NULL DEFAULT 1,
        ${DbConstants.colLast4} TEXT
      )
    ''');
  }

  static Future<void> _createGoalsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbConstants.tableGoals}(
        ${DbConstants.colId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colName} TEXT NOT NULL,
        ${DbConstants.colTargetAmount} INTEGER NOT NULL,
        ${DbConstants.colSavedAmount} INTEGER NOT NULL DEFAULT 0,
        ${DbConstants.colTargetDate} TEXT
      )
    ''');
  }

  static Future<void> _createRecurringTables(Database db) async {
    await db.execute('''
      CREATE TABLE ${DbConstants.tableRecurringRules}(
        ${DbConstants.colId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colDescription} TEXT,
        ${DbConstants.colAmount} INTEGER,
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
        ${DbConstants.colAmount} INTEGER,
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
    await clearGoals();
    // Wiping the ledger has to drop the dismissal list too, or messages the
    // user rejected stay suppressed against a database that no longer has the
    // transactions they were rejected next to.
    await clearSmsIgnored();
  }

  /// Atomically replaces (or, when [clearFirst] is false, appends to) the
  /// database contents with [rowsByTable]. Runs inside one transaction so an
  /// interrupted or failing restore rolls back to the pre-restore state
  /// instead of leaving a wiped, half-filled database.
  Future<void> replaceAllData(
    Map<String, List<Map<String, Object?>>> rowsByTable, {
    bool clearFirst = true,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      if (clearFirst) {
        for (final table in _allTables) {
          await txn.delete(table);
        }
      }
      final batch = txn.batch();
      for (final table in _allTables) {
        for (final row in rowsByTable[table] ?? const []) {
          batch.insert(table, row);
        }
      }
      await batch.commit(noResult: true);
    });
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

  // --- At-rest encryption (opt-in) -----------------------------------------

  static const List<String> _allTables = [
    DbConstants.tableAccounts,
    DbConstants.tableExpenses,
    DbConstants.tableInvestments,
    DbConstants.tableBudgets,
    DbConstants.tableRecurringRules,
    DbConstants.tableTemplates,
    DbConstants.tableGoals,
    // Included so toggling at-rest encryption (which copies every table into a
    // fresh database) carries the dismissal list across. A restore-with-clear
    // does empty it, since a backup carries no rows for it — the only cost is
    // that previously dismissed messages reappear once in the review queue.
    DbConstants.tableSmsIgnored,
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

  Future<String> get _snapshotPath async =>
      join(await getDatabasesPath(), 'finance_pre_migration.json');

  Future<void> _writeSafetySnapshot(
      Map<String, List<Map<String, Object?>>> data) async {
    await File(await _snapshotPath).writeAsString(jsonEncode(data));
  }

  /// Removes the plaintext pre-migration snapshot once a cipher migration has
  /// been verified, so no readable copy of the data is left on disk.
  Future<void> _deleteSafetySnapshot() async {
    try {
      final file = File(await _snapshotPath);
      if (await file.exists()) await file.delete();
    } catch (e) {
      AppLogger.error('Failed to delete pre-migration snapshot', e);
    }
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
    // Success: don't leave a plaintext copy of the data next to the
    // freshly encrypted database.
    await _deleteSafetySnapshot();
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
    await _deleteSafetySnapshot();
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
    return await db.delete(DbConstants.tableBudgets,
        where: '${DbConstants.colId} = ?', whereArgs: [id]);
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
    // Detach the account from transactions, recurring rules, and templates
    // in one transaction so nothing keeps a dangling reference to (or keeps
    // posting into) a deleted account.
    return await db.transaction((txn) async {
      await txn.update(
        DbConstants.tableExpenses,
        {DbConstants.colAccountId: null},
        where: '${DbConstants.colAccountId} = ?',
        whereArgs: [id],
      );
      await txn.update(
        DbConstants.tableExpenses,
        {DbConstants.colToAccountId: null},
        where: '${DbConstants.colToAccountId} = ?',
        whereArgs: [id],
      );
      await txn.update(
        DbConstants.tableRecurringRules,
        {DbConstants.colAccountId: null},
        where: '${DbConstants.colAccountId} = ?',
        whereArgs: [id],
      );
      await txn.update(
        DbConstants.tableTemplates,
        {DbConstants.colAccountId: null},
        where: '${DbConstants.colAccountId} = ?',
        whereArgs: [id],
      );
      return await txn.delete(DbConstants.tableAccounts,
          where: '${DbConstants.colId} = ?', whereArgs: [id]);
    });
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

  // Savings goal CRUD
  Future<int> insertGoal(Goal goal) async {
    final db = await database;
    return await db.insert(DbConstants.tableGoals, goal.toMap());
  }

  Future<List<Goal>> getGoals() async {
    final db = await database;
    final maps = await db.query(DbConstants.tableGoals,
        orderBy: '${DbConstants.colId} DESC');
    final goals = <Goal>[];
    for (final map in maps) {
      try {
        goals.add(Goal.fromMap(map));
      } catch (e, st) {
        AppLogger.error('Failed to parse goal row', e, st);
      }
    }
    return goals;
  }

  Future<int> updateGoal(Goal goal) async {
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

  Future<void> clearSmsIgnored() async {
    final db = await database;
    await db.delete(DbConstants.tableSmsIgnored);
  }

  /// Net worth (base-currency minor units) at the end of each of the last
  /// [months] months, oldest first. Net worth = account opening balances +
  /// cumulative (income − expense) + cumulative investments, as of each month
  /// end, with every account's flows converted at its exchange rate so the
  /// trend agrees with the headline figure. Same-currency transfers cancel;
  /// cross-currency transfers move value at the rates captured on the row.
  ///
  /// Three grouped queries + accumulation in Dart, instead of one query per
  /// month per flow type.
  Future<List<NetWorthPoint>> netWorthSeries(int months,
      {DateTime? now}) async {
    final db = await database;
    final today = now ?? DateTime.now();

    final accounts = await getAccounts();
    final rateById = {for (final a in accounts) a.id!: a.rate};
    double rateOf(Object? accountId) =>
        accountId == null ? 1.0 : (rateById[accountId] ?? 1.0);
    // Deleting an account nulls accountId/toAccountId on the rows that
    // referenced it. For a transfer that means one leg now points nowhere:
    // the money did not actually move into or out of anything we still track,
    // so that leg must not affect net worth. Counting it (at rate 1.0, no
    // less) made the trend diverge permanently from the account balances,
    // which exclude these rows outright — see getAccountFlows.
    bool isLiveAccount(Object? accountId) =>
        accountId != null && rateById.containsKey(accountId);
    final opening = accounts.fold<int>(
        0, (sum, a) => sum + toBaseMinor(a.openingBalance, a.rate));

    // ISO-8601 dates sort lexicographically, so substr(date, 1, 7) is the
    // row's YYYY-MM month key.
    final txRows = await db.rawQuery(
        'SELECT substr(${DbConstants.colDate}, 1, 7) AS ym, '
        '${DbConstants.colType} AS type, '
        '${DbConstants.colAccountId} AS accountId, '
        '${DbConstants.colToAccountId} AS toAccountId, '
        'SUM(${DbConstants.colAmount}) AS amt, '
        'SUM(COALESCE(${DbConstants.colToAmount}, ${DbConstants.colAmount})) AS toAmt '
        'FROM ${DbConstants.tableExpenses} '
        'GROUP BY ym, type, accountId, toAccountId');
    final invRows =
        await db.rawQuery('SELECT substr(${DbConstants.colDate}, 1, 7) AS ym, '
            'SUM(${DbConstants.colAmount}) AS amt '
            'FROM ${DbConstants.tableInvestments} GROUP BY ym');

    // Net base-currency change per month.
    final deltaByMonth = <String, double>{};
    void addDelta(Object? ym, double value) {
      if (ym is! String) return;
      deltaByMonth[ym] = (deltaByMonth[ym] ?? 0) + value;
    }

    for (final row in txRows) {
      final amt = ((row['amt'] ?? 0) as num).toDouble();
      final toAmt = ((row['toAmt'] ?? 0) as num).toDouble();
      switch (row['type']) {
        case DbConstants.txIncome:
          addDelta(row['ym'], amt * rateOf(row['accountId']));
        case DbConstants.txExpense:
          addDelta(row['ym'], -amt * rateOf(row['accountId']));
        case DbConstants.txTransfer:
          var delta = 0.0;
          if (isLiveAccount(row['accountId'])) {
            delta -= amt * rateOf(row['accountId']);
          }
          if (isLiveAccount(row['toAccountId'])) {
            delta += toAmt * rateOf(row['toAccountId']);
          }
          addDelta(row['ym'], delta);
      }
    }
    for (final row in invRows) {
      addDelta(row['ym'], ((row['amt'] ?? 0) as num).toDouble());
    }

    String ymKey(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

    // Accumulate every month's delta oldest-first; emit the running value at
    // each of the requested month ends.
    final sortedMonths = deltaByMonth.keys.toList()..sort();
    final series = <NetWorthPoint>[];
    var running = opening.toDouble();
    var next = 0;
    for (int i = months - 1; i >= 0; i--) {
      final monthStart = DateTime(today.year, today.month - i, 1);
      final key = ymKey(monthStart);
      while (next < sortedMonths.length &&
          sortedMonths[next].compareTo(key) <= 0) {
        running += deltaByMonth[sortedMonths[next]]!;
        next++;
      }
      series.add(NetWorthPoint(month: monthStart, value: running.round()));
    }
    return series;
  }

  /// Net transaction flow per account (minor units, in each account's own
  /// currency): income − expenses − outgoing transfers + incoming transfers.
  /// One pass over the table instead of four queries per account. Incoming
  /// cross-currency transfers credit the destination-side amount.
  Future<Map<int, int>> getAccountFlows() async {
    final db = await database;
    final flows = <int, double>{};

    final outRows =
        await db.rawQuery('SELECT ${DbConstants.colAccountId} AS accountId, '
            '${DbConstants.colType} AS type, '
            'SUM(${DbConstants.colAmount}) AS amt '
            'FROM ${DbConstants.tableExpenses} '
            'WHERE ${DbConstants.colAccountId} IS NOT NULL '
            'GROUP BY accountId, type');
    for (final row in outRows) {
      final id = row['accountId'] as int;
      final amt = ((row['amt'] ?? 0) as num).toDouble();
      final sign = row['type'] == DbConstants.txIncome ? 1 : -1;
      flows[id] = (flows[id] ?? 0) + sign * amt;
    }

    final inRows = await db.rawQuery(
        'SELECT ${DbConstants.colToAccountId} AS accountId, '
        'SUM(COALESCE(${DbConstants.colToAmount}, ${DbConstants.colAmount})) AS amt '
        'FROM ${DbConstants.tableExpenses} '
        'WHERE ${DbConstants.colType} = ? '
        'AND ${DbConstants.colToAccountId} IS NOT NULL '
        'GROUP BY accountId',
        [DbConstants.txTransfer]);
    for (final row in inRows) {
      final id = row['accountId'] as int;
      flows[id] = (flows[id] ?? 0) + ((row['amt'] ?? 0) as num).toDouble();
    }

    return flows.map((id, v) => MapEntry(id, v.round()));
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

  /// Every sourceRef already accounted for: imported as a transaction, or
  /// dismissed in the review queue. A rescan filters its candidates through
  /// this so neither an imported message nor a rejected one comes back.
  Future<Set<String>> existingSourceRefs() async {
    final db = await database;
    final imported = await db.rawQuery(
        'SELECT ${DbConstants.colSourceRef} AS ref FROM ${DbConstants.tableExpenses} '
        'WHERE ${DbConstants.colSourceRef} IS NOT NULL');
    final ignored = await db.rawQuery(
        'SELECT ${DbConstants.colSourceRef} AS ref FROM ${DbConstants.tableSmsIgnored}');
    return {
      for (final row in [...imported, ...ignored])
        if (row['ref'] is String) row['ref'] as String,
    };
  }

  /// Records that the user dismissed these messages in the review queue.
  Future<void> ignoreSourceRefs(Iterable<String> refs) async {
    if (refs.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final ref in refs) {
        batch.insert(
          DbConstants.tableSmsIgnored,
          {DbConstants.colSourceRef: ref},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Balance = opening + net flows, in the account's own currency.
  /// Computed in SQL so it covers all years, not just those loaded into
  /// ExpenseProvider. Prefer [getAccountFlows] when refreshing every account.
  Future<int> getAccountBalance(Account account) async {
    final flows = await getAccountFlows();
    return account.openingBalance + (flows[account.id] ?? 0);
  }
}
