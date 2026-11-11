import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/services/backup_service.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Turning database encryption on or off deletes the database and refills a
/// fresh one from a snapshot file. A kill in between used to leave an empty
/// database on the next launch, with the data stranded in a file nothing read.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'migration_recovery_test.db';

  final db = DBService();

  Future<void> seed() async {
    await db.clearAll();
    final accountId =
        await db.insertAccount(Account(name: 'Bank', type: 'bank'));
    await db.insertExpense(Expense(
      description: 'Lunch',
      amount: 25050,
      date: DateTime(2026, 3, 4, 13, 30),
      category: 'Food',
      paymentMode: 'UPI',
      accountId: accountId,
    ));
  }

  tearDown(() async {
    await db.clearAll();
    await db.close();
  });

  test('an interrupted migration is finished on the next open', () async {
    await seed();
    await db.debugInterruptMigration();

    // The next access reopens the (now empty) database.
    final expenses = await db.getExpenses();
    expect(expenses, hasLength(1));
    expect(expenses.single.description, 'Lunch');
    expect(expenses.single.amount, 25050);
    expect(expenses.single.date, DateTime(2026, 3, 4, 13, 30));
    final accounts = await db.getAccounts();
    expect(accounts.single.name, 'Bank');
    expect(expenses.single.accountId, accounts.single.id);
    // No plaintext copy is left behind.
    expect(await db.debugSnapshotExists(), isFalse);
  });

  test('a leftover snapshot beside intact data is only removed', () async {
    await seed();
    await db.debugInterruptMigration(wipe: false);

    expect(await db.getExpenses(), hasLength(1));
    expect(await db.getAccounts(), hasLength(1));
    expect(await db.debugSnapshotExists(), isFalse);
  });

  test('the Drive stamp is Drive\'s own modified time, in local time', () {
    final phone = DateTime(2026, 11, 11, 9, 0, 0);
    // Drive's clock is 40 s ahead of the phone's.
    final onDrive = phone.add(const Duration(seconds: 40)).toUtc();
    final stamp = BackupService.driveStamp(onDrive, phone);
    expect(stamp.isUtc, isFalse);
    expect(stamp.isAtSameMomentAs(onDrive), isTrue);
    // The copy this phone just uploaded must not look newer than the stamp.
    expect(onDrive.isAfter(stamp), isFalse);
    // Drive gave no time: fall back to the phone's.
    expect(BackupService.driveStamp(null, phone), phone);
  });
}
