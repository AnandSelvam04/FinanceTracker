import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/tx_template.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'template_payment_mode_test.db';

  setUp(() async => DBService().clearAll());
  tearDown(() async => DBService().clearAll());

  test('a template keeps its payment mode', () async {
    await DBService().insertTemplate(TxTemplate(
        name: 'Fuel',
        description: 'Fuel',
        amount: 200000,
        category: 'Transport',
        paymentMode: 'Credit Card'));
    expect(
        (await DBService().getTemplates()).single.paymentMode, 'Credit Card');
  });

  test('templates from older backups read back with no payment mode', () {
    final t = TxTemplate.fromMap({
      DbConstants.colName: 'Tea',
      DbConstants.colDescription: 'Tea',
      DbConstants.colAmount: 2000,
      DbConstants.colCategory: 'Food',
    });
    expect(t.paymentMode, isNull);
  });
}
