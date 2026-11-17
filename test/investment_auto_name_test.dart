import 'package:finance_tracker/models/investment.dart';
import 'package:finance_tracker/models/recurring_rule.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/services/recurring_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('a blank name becomes the type and month', () {
    Investment entry(String name, String type, {int amount = 100000}) =>
        Investment(
            name: name,
            amount: amount,
            date: DateTime(2026, 11, 3),
            type: type);

    test('for a custom type such as PPF', () {
      expect(entry('', 'PPF').name, 'PPF Nov 2026');
    });

    test('for every built-in type', () {
      for (final type in Investment.builtInTypes) {
        expect(entry('', type).name, '$type Nov 2026');
      }
    });

    test('spaces alone count as blank', () {
      expect(entry('   ', 'NPS').name, 'NPS Nov 2026');
    });

    test('a withdrawal says so', () {
      expect(entry('', 'Gold', amount: -5000).name, 'Gold Withdrawal Nov 2026');
    });

    test('a typed name is kept', () {
      expect(entry('Sukanya account', 'PPF').name, 'Sukanya account');
    });

    test('a row saved blank by an older build reads back named', () {
      final row = {
        DbConstants.colId: 4,
        DbConstants.colName: '',
        DbConstants.colAmount: 150000,
        DbConstants.colDate: DateTime(2025, 4, 10).toIso8601String(),
        DbConstants.colType: 'PPF',
      };
      expect(Investment.fromMap(row).name, 'PPF Apr 2025');
      expect(Investment.fromMap({...row, DbConstants.colName: null}).name,
          'PPF Apr 2025');
    });
  });

  group('through the database', () {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DBService.testFactory = databaseFactoryFfi;
    setUp(() async {
      DBService.dbNameOverride = 'investment_auto_name_test.db';
      await DBService().clearAll();
    });
    tearDown(() async => DBService().clearAll());

    test('a recurring SIP with no description posts named', () async {
      await DBService().insertRecurringRule(RecurringRule(
          description: '',
          amount: 50000,
          category: 'PPF',
          frequency: 'monthly',
          nextDue: DateTime(2026, 10, 5),
          isInvestment: true));
      await RecurringService.instance
          .postDueTransactions(now: DateTime(2026, 11, 7));
      final names = [
        for (final i in await DBService().getInvestments()) i.name
      ];
      expect(names, ['PPF Nov 2026', 'PPF Oct 2026']);
    });
  });
}
