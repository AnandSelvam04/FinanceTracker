import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers [DBService.splitExpense]: replacing one row with several that sum to
/// it, atomically, keeping the import link.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'split_expense_test.db';

  setUp(() async => DBService().clearAll());

  Expense part(int amount, String category) => Expense(
        description: 'AMAZON',
        amount: amount,
        date: DateTime(2025, 8, 10),
        category: category,
        paymentMode: 'Other',
        accountId: 1,
        sourceRef: 'sms:x:1:a',
      );

  test('replaces the original with parts that sum to it', () async {
    final id = await DBService().insertExpense(part(200000, 'Shopping'));

    await DBService()
        .splitExpense(id, [part(150000, 'Shopping'), part(50000, 'Gift')]);

    final rows = await DBService().getExpenses();
    expect(rows.length, 2);
    expect(rows.map((e) => e.category).toSet(), {'Shopping', 'Gift'});
    expect(rows.fold<int>(0, (s, e) => s + e.amount), 200000);
    // The original row is gone, replaced by the parts.
    expect(rows.any((e) => e.id == id), isFalse);
  });

  test('keeps the sourceRef so a rescan still treats it as handled', () async {
    final id = await DBService().insertExpense(part(200000, 'Shopping'));
    await DBService()
        .splitExpense(id, [part(150000, 'Shopping'), part(50000, 'Gift')]);
    expect(await DBService().existingSourceRefs(), contains('sms:x:1:a'));
  });

  test('the split parts move the account balance exactly as the original did',
      () async {
    final id = await DBService().insertExpense(part(200000, 'Shopping'));
    await DBService()
        .splitExpense(id, [part(120000, 'Shopping'), part(80000, 'Gift')]);
    // One account (id 1), two expenses totalling 200000 out.
    expect((await DBService().getAccountFlows())[1], -200000);
  });
}
