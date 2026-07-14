import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/currency_format.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

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

  test('v6 accounts migrate to v7 with default currency/rate', () async {
    DBService.dbNameOverride = 'mc_migration_test.db';
    final path = join(await getDatabasesPath(), 'mc_migration_test.db');
    await databaseFactory.deleteDatabase(path);

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
        },
      ),
    );
    await v6.insert('accounts',
        {'name': 'Cash', 'type': 'cash', 'openingBalance': 5000});
    await v6.close();

    // Opening through DBService runs the v7 migration (adds currency + rate).
    final accounts = await DBService().getAccounts();
    expect(accounts.length, 1);
    expect(accounts.first.name, 'Cash');
    expect(accounts.first.currency, isNull);
    expect(accounts.first.rate, 1.0);
  });
}
