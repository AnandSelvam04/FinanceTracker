import 'package:flutter_test/flutter_test.dart';
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
  });
}
