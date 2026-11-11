import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/services/receipt_store.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:finance_tracker/utils/tags.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;

  Expense tx(String description,
          {int amount = 100000,
          String? note,
          String type = DbConstants.txExpense,
          String? attachment}) =>
      Expense(
        description: description,
        amount: amount,
        date: DateTime(2026, 11, 1),
        category: 'Travel',
        paymentMode: 'UPI',
        type: type,
        note: note,
        attachment: attachment,
      );

  group('tags', () {
    test('found in notes, lower-cased, without repeats', () {
      expect(tagsIn('Dinner #Goa-Trip with #office #goa-trip'),
          ['goa-trip', 'office']);
      expect(tagsIn('Room 5 #2026'), ['2026']);
    });

    test('not in emails, links or a lone #', () {
      expect(tagsIn('mail a@b.com#x'), isEmpty);
      expect(tagsIn('Item # 4'), isEmpty);
      expect(tagsIn('Tea #-'), isEmpty);
      expect(tagsIn(null), isEmpty);
    });

    test('totals per tag: spend less refunds, income apart', () {
      final rows = [
        tx('Flight', amount: 800000, note: '#goa'),
        tx('Hotel', amount: 1200000, note: '#goa #work'),
        tx('Refund', amount: -100000, note: '#goa'),
        tx('Reimbursed',
            amount: 500000, note: '#work', type: DbConstants.txIncome),
      ];
      final t = tagSummaries(rows, (e) => e.amount);
      expect(t.map((s) => s.tag), ['goa', 'work']);
      expect(t.first.spent, 1900000);
      expect(t.first.transactions.length, 3);
      expect(t.last.spent, 1200000);
      expect(t.last.income, 500000);
    });
  });

  group('receipt photos', () {
    late Directory tmp;
    setUp(() async {
      DBService.dbNameOverride = 'receipts_test.db';
      await DBService().clearAll();
      tmp = await Directory.systemTemp.createTemp('receipts');
      ReceiptStore.baseOverride = tmp;
    });
    tearDown(() async {
      ReceiptStore.baseOverride = null;
      await DBService().clearAll();
      await tmp.delete(recursive: true);
    });

    test('kept with the transaction, and pruned once it is gone', () async {
      final photo = File('${tmp.path}/camera.jpg')..writeAsBytesSync([1, 2, 3]);
      final path = await ReceiptStore.save(photo.path);
      expect(path, startsWith('receipts/'));
      final id = await DBService().insertExpense(tx('Hotel', attachment: path));
      final saved = (await DBService().getExpenses()).single;
      expect(saved.attachment, path);
      expect((await ReceiptStore.fileFor(path)).existsSync(), isTrue);

      // Still referenced: kept.
      expect(await ReceiptStore.prune(), 0);
      await DBService().deleteExpense(id);
      expect(await ReceiptStore.prune(), 1);
      expect((await ReceiptStore.fileFor(path)).existsSync(), isFalse);
    });

    test('a photo that is not on this phone is detached (after a restore)',
        () async {
      final photo = File('${tmp.path}/camera.jpg')..writeAsBytesSync([1, 2, 3]);
      final here = await ReceiptStore.save(photo.path);
      await DBService().insertExpense(tx('Hotel', attachment: here));
      // As restored from another phone's backup: the path, but no image.
      await DBService()
          .insertExpense(tx('Flight', attachment: 'receipts/r1.jpg'));
      await DBService()
          .insertExpense(tx('Taxi', attachment: 'receipts/r1.jpg'));

      expect(await ReceiptStore.forgetMissing(), 2);
      final rows = {
        for (final e in await DBService().getExpenses())
          e.description: e.attachment
      };
      expect(rows, {'Hotel': here, 'Flight': null, 'Taxi': null});
      expect(await ReceiptStore.forgetMissing(), 0);
    });

    test('rows from before v21 have no photo', () {
      final e = Expense.fromMap({
        'description': 'Old',
        'amount': 100,
        'date': '2025-01-01T00:00:00.000',
        'category': 'Food',
        'paymentMode': 'Cash',
      });
      expect(e.attachment, isNull);
    });
  });
}
