import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/db_constants.dart';

/// The database schema: the tables a fresh install creates ([onCreate]) and
/// the step-by-step migrations an older database runs to reach
/// [DbConstants.dbVersion] ([onUpgrade]).
///
/// Kept apart from `DBService`, which only opens the database and runs
/// queries against it, so a schema change is made — and reviewed — in one
/// place.
///
/// When adding a version: bump [DbConstants.dbVersion], add the column or
/// table to the `create…` helper that [onCreate] runs, and add a guarded
/// `if (oldVersion < N)` step to [onUpgrade]. sqflite runs both inside a
/// transaction, so a failing step rolls the whole upgrade back.
class DbSchema {
  DbSchema._();

  static Future<void> onCreate(Database db, int version) async {
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
            ${DbConstants.colSourceRef} TEXT,
            ${DbConstants.colNote} TEXT,
            ${DbConstants.colAttachment} TEXT
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
            ${DbConstants.colType} TEXT,
            ${DbConstants.colAccountId} INTEGER
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
    await _createInvestmentValuesTable(db);
    await _createEmiPlansTable(db);
  }

  static Future<void> onUpgrade(
      Database db, int oldVersion, int newVersion) async {
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
      // Optional end date for recurring rules. Added after the v9 rebuild (see
      // _migrateAmountsToInteger, which recreates recurring_rules without this
      // column) so the ALTER never hits a duplicate column. Guarded on the
      // table existing: some databases reached this point without it (a v9
      // rebuild skips a table it doesn't have), and the ALTER must not fail
      // the whole upgrade in that case.
      final hasRecurring = await db.rawQuery(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
          [DbConstants.tableRecurringRules]);
      if (hasRecurring.isNotEmpty) {
        await db.execute(
            'ALTER TABLE ${DbConstants.tableRecurringRules} ADD COLUMN ${DbConstants.colEndDate} TEXT');
      }
    }
    if (oldVersion < 12) {
      // Flag marking a recurring rule as an investment contribution (SIP).
      // Same defensive pattern as the v11 endDate column: added after the v9
      // rebuild, and skipped when the table is absent so the upgrade can't
      // fail on a database that never had recurring_rules.
      final hasRecurring = await db.rawQuery(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
          [DbConstants.tableRecurringRules]);
      if (hasRecurring.isNotEmpty) {
        await db.execute(
            'ALTER TABLE ${DbConstants.tableRecurringRules} ADD COLUMN '
            '${DbConstants.colIsInvestment} INTEGER NOT NULL DEFAULT 0');
      }
    }
    if (oldVersion < 13) {
      // Credit-card billing cycle: statement day + payment due day. Guarded on
      // the accounts table existing, since a database that never had accounts
      // (created before v4) reaches this point without one.
      final hasAccounts = await db.rawQuery(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
          [DbConstants.tableAccounts]);
      if (hasAccounts.isNotEmpty) {
        await db.execute(
            'ALTER TABLE ${DbConstants.tableAccounts} ADD COLUMN ${DbConstants.colStatementDay} INTEGER');
        await db.execute(
            'ALTER TABLE ${DbConstants.tableAccounts} ADD COLUMN ${DbConstants.colDueDay} INTEGER');
      }
    }
    if (oldVersion < 14) {
      await _createGoalsTable(db);
    }
    if (oldVersion < 15) {
      // The account an investment was paid from, so buying one lowers that
      // balance (or adds to a credit card's bill). Existing rows stay
      // unlinked and keep not touching any balance. Guarded like v12/v13.
      final hasInvestments = await db.rawQuery(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
          [DbConstants.tableInvestments]);
      if (hasInvestments.isNotEmpty) {
        await db
            .execute('ALTER TABLE ${DbConstants.tableInvestments} ADD COLUMN '
                '${DbConstants.colAccountId} INTEGER');
      }
      await _createInvestmentValuesTable(db);
    }
    if (oldVersion < 16) {
      // Quick-add templates remember the payment mode; they used to post as
      // "Other" whatever the original was. After the v9 rebuild, which
      // recreates templates without it. Guarded like v12/v13.
      final hasTemplates = await db.rawQuery(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
          [DbConstants.tableTemplates]);
      if (hasTemplates.isNotEmpty) {
        await db.execute('ALTER TABLE ${DbConstants.tableTemplates} '
            'ADD COLUMN ${DbConstants.colPaymentMode} TEXT');
      }
    }
    if (oldVersion < 17) {
      // A free-text note on a transaction ("split with Ravi", "warranty till
      // 2028"). After the v9 rebuild, which recreates expenses without it.
      await db.execute('ALTER TABLE ${DbConstants.tableExpenses} '
          'ADD COLUMN ${DbConstants.colNote} TEXT');
    }
    if (oldVersion < 18) {
      // A credit card's limit, for the dashboard's usage bar. Guarded like
      // v13: a database from before v4 reaches here without accounts.
      final hasAccounts = await db.rawQuery(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
          [DbConstants.tableAccounts]);
      if (hasAccounts.isNotEmpty) {
        await db.execute('ALTER TABLE ${DbConstants.tableAccounts} '
            'ADD COLUMN ${DbConstants.colCreditLimit} INTEGER');
      }
    }
    if (oldVersion < 19) {
      // Two cards on one credit limit (a Visa and a RuPay card from the same
      // bank). Guarded like v18.
      final hasAccounts = await db.rawQuery(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
          [DbConstants.tableAccounts]);
      if (hasAccounts.isNotEmpty) {
        await db.execute('ALTER TABLE ${DbConstants.tableAccounts} '
            'ADD COLUMN ${DbConstants.colSharedLimitWith} INTEGER');
      }
    }
    if (oldVersion < 20) {
      await _createEmiPlansTable(db);
    }
    if (oldVersion < 22) {
      // A card's reward points. Guarded like v18.
      final hasAccounts = await db.rawQuery(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
          [DbConstants.tableAccounts]);
      if (hasAccounts.isNotEmpty) {
        for (final col in [
          '${DbConstants.colRewardPoints} INTEGER',
          '${DbConstants.colRewardAsOf} TEXT',
          '${DbConstants.colRewardRate} REAL',
          '${DbConstants.colPointValue} REAL',
        ]) {
          await db.execute(
              'ALTER TABLE ${DbConstants.tableAccounts} ADD COLUMN $col');
        }
      }
    }
    if (oldVersion < 21) {
      // A receipt photo on a transaction. After the v9 rebuild of expenses.
      await db.execute('ALTER TABLE ${DbConstants.tableExpenses} '
          'ADD COLUMN ${DbConstants.colAttachment} TEXT');
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
        ${DbConstants.colLast4} TEXT,
        ${DbConstants.colStatementDay} INTEGER,
        ${DbConstants.colDueDay} INTEGER,
        ${DbConstants.colCreditLimit} INTEGER,
        ${DbConstants.colSharedLimitWith} INTEGER,
        ${DbConstants.colRewardPoints} INTEGER,
        ${DbConstants.colRewardAsOf} TEXT,
        ${DbConstants.colRewardRate} REAL,
        ${DbConstants.colPointValue} REAL
      )
    ''');
  }

  static Future<void> _createInvestmentValuesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbConstants.tableInvestmentValues}(
        ${DbConstants.colType} TEXT PRIMARY KEY,
        ${DbConstants.colAmount} INTEGER NOT NULL,
        ${DbConstants.colDate} TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createEmiPlansTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbConstants.tableEmiPlans}(
        ${DbConstants.colId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colEmiCardId} INTEGER NOT NULL,
        ${DbConstants.colEmiLoanId} INTEGER NOT NULL,
        ${DbConstants.colDescription} TEXT NOT NULL,
        ${DbConstants.colEmiPrincipal} INTEGER NOT NULL,
        ${DbConstants.colEmiMonths} INTEGER NOT NULL,
        ${DbConstants.colEmiMonthly} INTEGER NOT NULL,
        ${DbConstants.colDate} TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createGoalsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbConstants.tableGoals}(
        ${DbConstants.colId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colName} TEXT NOT NULL,
        ${DbConstants.colAmount} INTEGER NOT NULL DEFAULT 0,
        ${DbConstants.colSaved} INTEGER NOT NULL DEFAULT 0,
        ${DbConstants.colDate} TEXT,
        ${DbConstants.colColor} INTEGER
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
        ${DbConstants.colEnabled} INTEGER NOT NULL DEFAULT 1,
        ${DbConstants.colEndDate} TEXT,
        ${DbConstants.colIsInvestment} INTEGER NOT NULL DEFAULT 0
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
        ${DbConstants.colAccountId} INTEGER,
        ${DbConstants.colPaymentMode} TEXT
      )
    ''');
  }
}
