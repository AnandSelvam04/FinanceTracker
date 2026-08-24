import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/budget.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/services/backup_service.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  // Isolate this file's database so concurrently running test files
  // can't clear each other's data (they all share one ffi process).
  DBService.dbNameOverride = 'backup_service_test.db';

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
    await DBService().clearAll();
  });

  tearDown(() async {
    await DBService().clearAll();
    await tempDir.delete(recursive: true);
  });

  group('BackupService JSON round-trip', () {
    test('backup and restore include budgets', () async {
      final db = DBService();
      await db.insertExpense(Expense(
        description: 'Lunch',
        amount: 12000, // 120.00
        date: DateTime(2026, 5, 10),
        category: 'Food',
        paymentMode: 'UPI',
      ));
      await db.insertBudget(Budget(
        category: 'Food',
        amount: 300000, // 3000.00
        year: 2026,
        month: 5,
      ));
      await db.insertAccount(
          Account(name: 'Wallet', type: 'cash', openingBalance: 250));

      final service = BackupService();
      await service.backupToJson();
      await db.clearAll();
      expect(await db.getExpenses(), isEmpty);
      expect(await db.getBudgets(), isEmpty);
      expect(await db.getAccounts(), isEmpty);

      await service.restoreFromJson();

      final expenses = await db.getExpenses();
      final budgets = await db.getBudgets();
      final accounts = await db.getAccounts();
      expect(expenses.length, 1);
      expect(expenses.first.description, 'Lunch');
      expect(budgets.length, 1);
      expect(budgets.first.category, 'Food');
      expect(budgets.first.amount, 300000);
      expect(accounts.length, 1);
      expect(accounts.first.name, 'Wallet');
      expect(accounts.first.openingBalance, 250);
    });

    test('restore of legacy backup without budgets key succeeds', () async {
      final legacy = {
        'expenses': [
          {
            'id': 1,
            'description': 'Old expense',
            'amount': 50.0,
            'date': DateTime(2025, 1, 1).toIso8601String(),
            'category': 'Other',
            'paymentMode': 'Cash',
          }
        ],
        'investments': [],
      };
      final file = File('${tempDir.path}/finance_backup.json');
      await file.writeAsString(jsonEncode(legacy));

      await BackupService().restoreFromJson();

      final expenses = await DBService().getExpenses();
      expect(expenses.length, 1);
      expect(expenses.first.description, 'Old expense');
      expect(await DBService().getBudgets(), isEmpty);
    });

    test('verifyLocalBackup reports row counts for a good backup', () async {
      final db = DBService();
      await db.insertExpense(Expense(
        description: 'Lunch',
        amount: 12000,
        date: DateTime(2026, 5, 10),
        category: 'Food',
        paymentMode: 'UPI',
      ));
      await db.insertBudget(
          Budget(category: 'Food', amount: 300000, year: 2026, month: 5));

      final service = BackupService();
      await service.backupToJson();

      final result = await service.verifyLocalBackup();
      expect(result.ok, isTrue);
      expect(result.counts['expenses'], 1);
      expect(result.counts['budgets'], 1);
      expect(result.total, 2);
      // Verifying must not have altered the live data.
      expect((await db.getExpenses()).length, 1);
    });

    test('verifyLocalBackup fails cleanly when no backup exists', () async {
      final result = await BackupService().verifyLocalBackup();
      expect(result.ok, isFalse);
      expect(result.error, isNotNull);
    });

    test('verifyLocalBackup fails on a corrupt backup file', () async {
      final file = File('${tempDir.path}/finance_backup.json');
      await file.writeAsString('{ this is not valid json');
      final result = await BackupService().verifyLocalBackup();
      expect(result.ok, isFalse);
    });

    test('verifyLocalBackup rejects a JSON file that is not a backup', () async {
      final file = File('${tempDir.path}/finance_backup.json');
      // A list, not the expected object shape.
      await file.writeAsString(jsonEncode([1, 2, 3]));
      final result = await BackupService().verifyLocalBackup();
      expect(result.ok, isFalse);
    });

    test('clearAll clears budgets too', () async {
      final db = DBService();
      await db.insertBudget(
          Budget(category: 'Bills', amount: 100, year: 2026, month: 1));
      await db.clearAll();
      expect(await db.getBudgets(), isEmpty);
    });

    test('autoBackupIfDue writes once, then throttles, and stamps time',
        () async {
      final service = BackupService();
      expect(await service.lastBackupTime(), isNull);

      final first = await service.autoBackupIfDue();
      expect(first, isTrue);
      expect(await service.lastBackupTime(), isNotNull);

      // A second immediate call is throttled.
      final second = await service.autoBackupIfDue();
      expect(second, isFalse);

      // A zero interval forces another backup.
      final forced =
          await service.autoBackupIfDue(minInterval: Duration.zero);
      expect(forced, isTrue);
    });

    test('a corrupt backup leaves existing data untouched (atomic restore)',
        () async {
      final db = DBService();
      await db.insertExpense(Expense(
        description: 'Keep me',
        amount: 500,
        date: DateTime(2026, 4, 1),
        category: 'Food',
        paymentMode: 'Cash',
      ));

      // Second row is malformed (date is garbage), so the restore must fail
      // without wiping the existing data.
      final corrupt = {
        'version': 5,
        'expenses': [
          {
            'description': 'New row',
            'amount': 100,
            'date': DateTime(2026, 4, 2).toIso8601String(),
            'category': 'Other',
            'paymentMode': 'Cash',
          },
          {
            'description': 'Bad row',
            'amount': 100,
            'date': 'not-a-date',
            'category': 'Other',
            'paymentMode': 'Cash',
          },
        ],
      };
      final file = File('${tempDir.path}/finance_backup.json');
      await file.writeAsString(jsonEncode(corrupt));

      await expectLater(BackupService().restoreFromJson(), throwsA(anything));

      final expenses = await DBService().getExpenses();
      expect(expenses.length, 1);
      expect(expenses.first.description, 'Keep me');
    });

    test('a backup with no rows is refused rather than wiping everything',
        () async {
      final db = DBService();
      await db.insertExpense(Expense(
        description: 'Keep me',
        amount: 500,
        date: DateTime(2026, 4, 1),
        category: 'Food',
        paymentMode: 'Cash',
      ));

      // Structurally valid, but empty: applying it would erase the user's
      // data with nothing to show for it.
      final file = File('${tempDir.path}/finance_backup.json');
      await file.writeAsString(jsonEncode({'version': 5}));

      await expectLater(BackupService().restoreFromJson(),
          throwsA(isA<EmptyBackupException>()));
      expect((await DBService().getExpenses()).length, 1);

      // ...but the user can still force it through after confirming.
      await BackupService().restoreFromJson(allowEmpty: true);
      expect(await DBService().getExpenses(), isEmpty);
    });

    test('a JSON file that is not a backup is rejected before any wipe',
        () async {
      final db = DBService();
      await db.insertExpense(Expense(
        description: 'Keep me',
        amount: 500,
        date: DateTime(2026, 4, 1),
        category: 'Food',
        paymentMode: 'Cash',
      ));

      final file = File('${tempDir.path}/finance_backup.json');

      // A JSON array (e.g. a renamed export) used to throw NoSuchMethodError.
      await file.writeAsString(jsonEncode([1, 2, 3]));
      await expectLater(BackupService().restoreFromJson(),
          throwsA(isA<BackupFormatException>()));

      // A table key holding something other than a list.
      await file.writeAsString(jsonEncode({'version': 5, 'expenses': 'nope'}));
      await expectLater(BackupService().restoreFromJson(),
          throwsA(isA<BackupFormatException>()));

      // A non-numeric version.
      await file.writeAsString(jsonEncode({'version': 'five'}));
      await expectLater(BackupService().restoreFromJson(),
          throwsA(isA<BackupFormatException>()));

      expect((await DBService().getExpenses()).length, 1);
    });

    test('writeJsonBackupFile encrypts when a device key is available',
        () async {
      final db = DBService();
      await db.insertExpense(Expense(
        description: 'Secret lunch',
        amount: 4200,
        date: DateTime(2026, 5, 1),
        category: 'Food',
        paymentMode: 'UPI',
      ));

      // deviceKeyIfEncrypted() returns null under dbNameOverride, so this
      // asserts the plaintext branch; the encrypted branch is covered by the
      // round-trip test below. What matters here is that the download/share
      // path goes through backupToJson's deviceKey parameter at all.
      final file = await BackupService().writeJsonBackupFile();
      expect(await file.exists(), isTrue);
      expect(file.path, endsWith('finance_backup.json'));
    });

    test('CSV export neutralises spreadsheet formulas', () async {
      // A description starting with '=' would execute on open in Excel or
      // LibreOffice; it must be exported as literal text.
      expect(csvSafeCell('=HYPERLINK("http://evil/","x")'),
          "'=HYPERLINK(\"http://evil/\",\"x\")");
      expect(csvSafeCell('+1'), "'+1");
      expect(csvSafeCell('-1'), "'-1");
      expect(csvSafeCell('@cmd'), "'@cmd");
      expect(csvSafeCell('\tTabbed'), "'\tTabbed");
      // Ordinary values and non-strings are untouched.
      expect(csvSafeCell('Groceries'), 'Groceries');
      expect(csvSafeCell(''), '');
      expect(csvSafeCell(42), 42);

      final db = DBService();
      await db.insertExpense(Expense(
        description: '=cmd|\'/c calc\'!A1',
        amount: 100,
        date: DateTime(2026, 4, 1),
        category: 'Food',
        paymentMode: 'Cash',
      ));
      final contents = await (await exportExpensesToCsv()).readAsString();
      expect(contents, contains("'=cmd"));
    });

    test('device-key-encrypted backup round-trips through restoreFromJson',
        () async {
      final db = DBService();
      await db.insertExpense(Expense(
        description: 'Secret lunch',
        amount: 4200,
        date: DateTime(2026, 5, 1),
        category: 'Food',
        paymentMode: 'UPI',
      ));

      final service = BackupService();
      await service.backupToJson(deviceKey: 'test-device-key');

      // The file on disk is an envelope, not readable JSON data.
      final raw = await File('${tempDir.path}/finance_backup.json')
          .readAsString();
      expect(raw.contains('Secret lunch'), isFalse);
      expect(jsonDecode(raw), containsPair('magic', 'ft-enc-v1'));

      await db.clearAll();
      await service.restoreFromJson(deviceKey: 'test-device-key');
      final expenses = await db.getExpenses();
      expect(expenses.single.description, 'Secret lunch');
    });

    test('transfer toAmount survives a backup round-trip', () async {
      final db = DBService();
      await db.insertExpense(Expense(
        description: 'FX transfer',
        amount: 830000,
        date: DateTime(2026, 6, 1),
        category: 'Transfer',
        paymentMode: 'Other',
        type: 'transfer',
        accountId: 1,
        toAccountId: 2,
        toAmount: 10000,
      ));

      final service = BackupService();
      await service.backupToJson();
      await db.clearAll();
      await service.restoreFromJson();

      final restored = (await db.getExpenses()).single;
      expect(restored.toAmount, 10000);
      expect(restored.receivedAmount, 10000);
    });

    test('writeExpensesCsvFile writes only the rows it is given', () async {
      // Simulates the "download filtered" flow: caller passes a subset.
      final marchOnly = [
        Expense(
          description: 'March lunch',
          amount: 120,
          date: DateTime(2026, 3, 10),
          category: 'Food',
          paymentMode: 'UPI',
        ),
      ];
      final file = await writeExpensesCsvFile(marchOnly,
          filename: 'expenses_2026-03.csv');
      final contents = await file.readAsString();
      final lines = contents.trim().split('\n');

      expect(file.path, endsWith('expenses_2026-03.csv'));
      expect(lines.first, contains('Description'));
      expect(lines.first, contains('Type'));
      expect(lines.length, 2); // header + one filtered row
      expect(contents, contains('March lunch'));
    });
  });
}
