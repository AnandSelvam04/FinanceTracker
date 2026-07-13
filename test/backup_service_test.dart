import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/budget.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/services/backup_service.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
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
        amount: 120.0,
        date: DateTime(2026, 5, 10),
        category: 'Food',
        paymentMode: 'UPI',
      ));
      await db.insertBudget(Budget(
        category: 'Food',
        amount: 3000.0,
        year: 2026,
        month: 5,
      ));

      final service = BackupService();
      await service.backupToJson();
      await db.clearAll();
      expect(await db.getExpenses(), isEmpty);
      expect(await db.getBudgets(), isEmpty);

      await service.restoreFromJson();

      final expenses = await db.getExpenses();
      final budgets = await db.getBudgets();
      expect(expenses.length, 1);
      expect(expenses.first.description, 'Lunch');
      expect(budgets.length, 1);
      expect(budgets.first.category, 'Food');
      expect(budgets.first.amount, 3000.0);
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
  });
}
