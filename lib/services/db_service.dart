import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/account.dart';
import '../models/expense.dart';
import '../models/investment.dart';
import '../models/budget.dart';
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

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, dbNameOverride ?? DbConstants.dbName);
    return await openDatabase(
      path,
      version: DbConstants.dbVersion,
      onCreate: (db, version) async {
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
      },
      onUpgrade: (db, oldVersion, newVersion) async {
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
      },
    );
  }

  static Future<void> _createAccountsTable(Database db) async {
    await db.execute('''
      CREATE TABLE ${DbConstants.tableAccounts}(
        ${DbConstants.colId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colName} TEXT NOT NULL,
        ${DbConstants.colType} TEXT NOT NULL,
        ${DbConstants.colOpeningBalance} REAL NOT NULL DEFAULT 0,
        ${DbConstants.colColor} INTEGER
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

  /// Balance = opening + income − expenses − outgoing transfers
  /// + incoming transfers. Computed in SQL so it covers all years,
  /// not just those loaded into ExpenseProvider.
  Future<double> getAccountBalance(Account account) async {
    final db = await database;

    Future<double> sumWhere(String where, List<Object?> args) async {
      final result = await db.rawQuery(
        'SELECT SUM(${DbConstants.colAmount}) AS total FROM ${DbConstants.tableExpenses} WHERE $where',
        args,
      );
      return ((result.first['total'] ?? 0) as num).toDouble();
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
