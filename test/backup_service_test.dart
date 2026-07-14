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
