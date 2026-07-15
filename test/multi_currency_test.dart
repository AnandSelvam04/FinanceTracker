import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/currency_format.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;

  // Pure logic first (no DBService access, so the singleton stays uninitialized
  // until the migration test opens the pre-seeded database).
  group('currency conversion + account model', () {
    setUp(() => CurrencyFormat.symbol = '₹');

    test('toBaseMinor converts account-currency minor units to base', () {
      expect(toBaseMinor(1000, 83.0), 83000); // $10.00 at 83 -> ₹830.00
      expect(toBaseMinor(1000, 1.0), 1000); // base currency unchanged
      expect(toBaseMinor(101, 1.5), 152); // rounds to nearest minor unit
    });

    test('Account round-trips currency and rate through toMap/fromMap', () {
      final a = Account(
          name: 'US', type: 'bank', openingBalance: 5000, currency: '\$', rate: 83);
      final restored = Account.fromMap(a.toMap());
      expect(restored.currency, '\$');
      expect(restored.rate, 83);
      expect(restored.symbol, '\$');
      expect(restored.isForeign, isTrue);
    });

    test('base-currency account defaults to symbol and rate 1', () {
      final a = Account(name: 'Cash', type: 'cash');
      expect(a.currency, isNull);
      expect(a.rate, 1.0);
      expect(a.symbol, '₹');
      expect(a.isForeign, isFalse);
    });
  });

  test('v6 database migrates to current version (currency/rate + toAmount)',
      () async {
    DBService.dbNameOverride = 'mc_migration_test.db';
    final path = join(await getDatabasesPath(), 'mc_migration_test.db');
    await databaseFactory.deleteDatabase(path);

    // Real v6 schema for the tables later migrations touch.
    final v6 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE accounts(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              openingBalance REAL NOT NULL DEFAULT 0,
              color INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE expenses(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              description TEXT,
              amount REAL,
              date TEXT,
              category TEXT,
              paymentMode TEXT,
              type TEXT NOT NULL DEFAULT 'expense',
              accountId INTEGER,
              toAccountId INTEGER
            )
          ''');
        },
      ),
    );
    await v6.insert('accounts',
        {'name': 'Cash', 'type': 'cash', 'openingBalance': 5000});
    await v6.insert('expenses', {
      'description': 'Old transfer',
      'amount': 700,
      'date': DateTime(2026, 1, 5).toIso8601String(),
      'category': 'Transfer',
      'paymentMode': 'Other',
      'type': 'transfer',
      'accountId': 1,
      'toAccountId': 1,
    });
    await v6.close();

    // Opening through DBService runs the v7 (currency + rate) and v8
    // (toAmount + indexes) migrations.
    final accounts = await DBService().getAccounts();
    expect(accounts.length, 1);
    expect(accounts.first.name, 'Cash');
    expect(accounts.first.currency, isNull);
    expect(accounts.first.rate, 1.0);

    // Pre-v8 transfers have no toAmount: destination side falls back to
    // the source amount.
    final expenses = await DBService().getExpenses();
    expect(expenses.single.toAmount, isNull);
    expect(expenses.single.receivedAmount, 700);
  });

  test('cross-currency transfer credits the destination-side amount',
      () async {
    // The previous test left the singleton on the synthetic v6 database;
    // reopen on a fresh full-schema database.
    await DBService().close();
    DBService.dbNameOverride = 'mc_transfer_test.db';
    final db = DBService();
    await db.clearAll();
    final inrId = await db.insertAccount(
        Account(name: 'INR Bank', type: 'bank', openingBalance: 1000000));
    final usdId = await db.insertAccount(Account(
        name: 'USD Bank',
        type: 'bank',
        openingBalance: 0,
        currency: '\$',
        rate: 83));

    // ₹8,300.00 leaves the INR account; $100.00 arrives in the USD account.
    await db.insertExpense(Expense(
      description: 'Send abroad',
      amount: 830000,
      date: DateTime(2026, 6, 1),
      category: 'Transfer',
      paymentMode: 'Other',
      type: 'transfer',
      accountId: inrId,
      toAccountId: usdId,
      toAmount: 10000,
    ));

    final accounts = await db.getAccounts();
    final inr = accounts.firstWhere((a) => a.id == inrId);
    final usd = accounts.firstWhere((a) => a.id == usdId);
    expect(await db.getAccountBalance(inr), 1000000 - 830000);
    expect(await db.getAccountBalance(usd), 10000); // $100, not ₹8,300
    await db.clearAll();
  });
}
