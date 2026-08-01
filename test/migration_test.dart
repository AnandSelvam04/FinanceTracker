import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;

  test('v3 database migrates to v4 with typed legacy rows', () async {
    DBService.dbNameOverride = 'migration_test.db';
    final path = join(await getDatabasesPath(), 'migration_test.db');
    await databaseFactory.deleteDatabase(path);

    // Build a database exactly as schema v3 created it.
    final v3db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE expenses(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              description TEXT,
              amount REAL,
              date TEXT,
              category TEXT,
              paymentMode TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE investments(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT,
              amount REAL,
              date TEXT,
              type TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE budgets(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              category TEXT,
              amount REAL,
              year INTEGER,
              month INTEGER
            )
          ''');
        },
      ),
    );
    await v3db.insert('expenses', {
      'description': 'Legacy row',
      'amount': 75.0,
      'date': DateTime(2025, 6, 1).toIso8601String(),
      'category': 'Food',
      'paymentMode': 'Cash',
    });
    await v3db.close();

    // Opening through DBService runs the v4..v6 migrations.
    final expenses = await DBService().getExpenses();
    expect(expenses.length, 1);
    expect(expenses.first.description, 'Legacy row');
    expect(expenses.first.type, DbConstants.txExpense);
    expect(expenses.first.accountId, isNull);
    // v6 converted the 75.00 rupee amount to integer minor units.
    expect(expenses.first.amount, 7500);

    // Accounts table exists and is empty.
    expect(await DBService().getAccounts(), isEmpty);

    // v9 gave every money column INTEGER affinity. Amounts had been integer
    // minor units since v6, but the columns were still declared REAL, so
    // SQLite coerced each one to a double on write.
    final db = await DBService().database;
    Future<String> affinityOf(String table, String column) async {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      return columns.firstWhere((c) => c['name'] == column)['type'] as String;
    }

    expect(await affinityOf(DbConstants.tableExpenses, DbConstants.colAmount),
        'INTEGER');
    expect(
        await affinityOf(DbConstants.tableInvestments, DbConstants.colAmount),
        'INTEGER');
    expect(await affinityOf(DbConstants.tableBudgets, DbConstants.colAmount),
        'INTEGER');
    expect(
        await affinityOf(
            DbConstants.tableAccounts, DbConstants.colOpeningBalance),
        'INTEGER');
    expect(
        await affinityOf(
            DbConstants.tableRecurringRules, DbConstants.colAmount),
        'INTEGER');
    expect(await affinityOf(DbConstants.tableTemplates, DbConstants.colAmount),
        'INTEGER');
    // `rate` is a genuine fraction and must stay REAL.
    expect(await affinityOf(DbConstants.tableAccounts, DbConstants.colRate),
        'REAL');

    // The stored value is now a true int, not a double that reads back as one.
    final raw = await db.rawQuery(
        'SELECT ${DbConstants.colAmount} AS a FROM ${DbConstants.tableExpenses}');
    expect(raw.first['a'], isA<int>());
    expect(raw.first['a'], 7500);

    // Dropping the expenses table dropped its indexes; v9 must put them back,
    // or the date-range and balance queries silently go back to full scans.
    final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = ?",
        [DbConstants.tableExpenses]);
    final names = indexes.map((r) => r['name']).toSet();
    expect(names, contains(DbConstants.idxExpensesDate));
    expect(names, contains(DbConstants.idxExpensesTypeAccount));
    expect(names, contains(DbConstants.idxExpensesToAccount));

    // v10 added the SMS-import columns. The v9 rebuild drops and recreates
    // expenses and accounts from a fixed column list, so these must be added
    // after it — if the order ever flips, the ALTERs fail on a duplicate
    // column and every upgrading install is left unopenable.
    expect(await affinityOf(DbConstants.tableExpenses, DbConstants.colSourceRef),
        'TEXT');
    expect(await affinityOf(DbConstants.tableAccounts, DbConstants.colLast4),
        'TEXT');
    expect(names, contains(DbConstants.idxExpensesSourceRef));

    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'");
    expect(tables.map((r) => r['name']), contains(DbConstants.tableSmsIgnored));

    // Rows that predate the column read back as null rather than failing.
    expect(expenses.first.sourceRef, isNull);
  });

  test('v10 tracks imported and dismissed sourceRefs', () async {
    DBService.dbNameOverride = 'source_ref_test.db';
    final path = join(await getDatabasesPath(), 'source_ref_test.db');
    await databaseFactory.deleteDatabase(path);

    // A hand-entered row contributes no sourceRef.
    await DBService().insertExpense(Expense(
      description: 'Typed by hand',
      amount: 1000,
      date: DateTime(2025, 8, 1),
      category: 'Food',
      paymentMode: 'Cash',
    ));
    expect(await DBService().existingSourceRefs(), isEmpty);

    await DBService().insertExpense(Expense(
      description: 'SWIGGY',
      amount: 49900,
      date: DateTime(2025, 8, 1),
      category: 'Food',
      paymentMode: 'Other',
      sourceRef: 'sms:vm-hdfcbk:1000:abcd1234',
    ));
    await DBService().ignoreSourceRefs(['sms:vm-icicib:2000:deadbeef']);

    // Both an imported message and a dismissed one count as seen, which is
    // what keeps a rescan from re-offering either.
    expect(
      await DBService().existingSourceRefs(),
      {'sms:vm-hdfcbk:1000:abcd1234', 'sms:vm-icicib:2000:deadbeef'},
    );

    // Dismissing twice is a no-op rather than a primary-key violation.
    await DBService().ignoreSourceRefs(['sms:vm-icicib:2000:deadbeef']);
    expect((await DBService().existingSourceRefs()).length, 2);

    // The sourceRef survives the round-trip to the database.
    final saved = (await DBService().getExpenses())
        .firstWhere((e) => e.description == 'SWIGGY');
    expect(saved.sourceRef, 'sms:vm-hdfcbk:1000:abcd1234');
  });
}
