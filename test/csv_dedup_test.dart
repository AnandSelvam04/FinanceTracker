import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/services/csv_import.dart';
import 'package:finance_tracker/services/db_service.dart';

/// Importing the same (or an overlapping) CSV statement twice must not double
/// the transactions in it.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'csv_dedup_test.db';

  const mapping = CsvColumnMapping(dateCol: 0, descriptionCol: 1, amountCol: 2);

  CsvImportResult parse(List<List<dynamic>> rows) =>
      parseCsvExpenses(rows, hasHeader: false, mapping: mapping);

  /// What the Import screen does: drop rows already imported, insert the rest.
  Future<CsvImportResult> importRows(List<List<dynamic>> rows) async {
    final result = parse(rows).withoutAlreadyImported(
        await DBService().existingSourceRefs(includeIgnored: false));
    await DBService().insertExpenses(result.expenses);
    return result;
  }

  setUp(() async => DBService().clearAll());

  group('csvSourceRef', () {
    test('ignores case, spacing, and time of day in the identity', () {
      final a = parse([
        ['2026-06-02', 'Big  Bazaar ', '1200'],
      ]).expenses.single;
      final b = parse([
        ['2026-06-02T18:30:00', 'big bazaar', '1,200.00'],
      ]).expenses.single;
      expect(a.sourceRef, b.sourceRef);
    });

    test('tells apart a different amount, day, or description', () {
      final refs = parse([
        ['2026-06-02', 'Coffee', '50'],
        ['2026-06-02', 'Coffee', '60'],
        ['2026-06-03', 'Coffee', '50'],
        ['2026-06-02', 'Tea', '50'],
      ]).expenses.map((e) => e.sourceRef).toSet();
      expect(refs.length, 4);
    });

    test('numbers identical rows within one file', () {
      final refs = parse([
        ['2026-06-02', 'Coffee', '50'],
        ['2026-06-02', 'Coffee', '50'],
      ]).expenses.map((e) => e.sourceRef).toList();
      expect(refs[0], endsWith('#1'));
      expect(refs[1], endsWith('#2'));
    });
  });

  test('importing the same file twice adds nothing the second time', () async {
    final file = [
      ['2026-06-01', 'Salary', '40000'],
      ['2026-06-02', 'Groceries', '-1200'],
      ['2026-06-02', 'Coffee', '-50'],
      ['2026-06-02', 'Coffee', '-50'], // a genuine second coffee
    ];
    final first = await importRows(file);
    expect(first.expenses.length, 4);

    final second = await importRows(file);
    expect(second.expenses, isEmpty);
    expect(second.duplicates, 4);
    expect((await DBService().getExpenses()).length, 4);
  });

  test('an overlapping statement imports only its new rows', () async {
    await importRows([
      ['2026-06-01', 'Rent', '-20000'],
      ['2026-06-05', 'Coffee', '-50'],
    ]);
    final next = await importRows([
      ['2026-06-05', 'Coffee', '-50'], // overlap
      ['2026-06-05', 'Coffee', '-50'], // a second coffee that day: new
      ['2026-06-09', 'Books', '-700'], // new
    ]);

    expect(next.duplicates, 1);
    expect(next.expenses.map((e) => e.description), ['Coffee', 'Books']);
    expect((await DBService().getExpenses()).length, 4);
  });

  test('a recategorised row still counts as imported', () async {
    await importRows([
      ['2026-06-02', 'Amazon', '-999'],
    ]);
    final row = (await DBService().getExpenses()).single;
    // What the edit sheet saves after the user refiles it.
    await DBService().updateExpense(Expense(
      id: row.id,
      description: row.description,
      amount: row.amount,
      date: row.date,
      category: 'Gifts',
      paymentMode: row.paymentMode,
      type: row.type,
      sourceRef: row.sourceRef,
    ));

    final again = await importRows([
      ['2026-06-02', 'Amazon', '-999'],
    ]);
    expect(again.expenses, isEmpty);
  });
}
