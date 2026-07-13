import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/investment.dart';
import 'package:finance_tracker/providers/investment_provider.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('InvestmentProvider Tests', () {
    late InvestmentProvider provider;

    setUp(() async {
      await DBService().clearAll();
      provider = InvestmentProvider();
    });

    tearDown(() async {
      await DBService().clearAll();
    });

    test('Add and fetch investments', () async {
      await provider.addInvestment(Investment(
        name: 'Index Fund',
        amount: 5000.0,
        date: DateTime(2026, 1, 15),
        type: 'Mutual Funds',
      ));

      expect(provider.investments.length, 1);
      expect(provider.investments.first.name, 'Index Fund');
      expect(provider.investments.first.amount, 5000.0);
    });

    test('Update investment', () async {
      await provider.addInvestment(Investment(
        name: 'FD',
        amount: 1000.0,
        date: DateTime(2026, 2, 1),
        type: 'FD',
      ));
      final saved = provider.investments.first;

      await provider.updateInvestment(Investment(
        id: saved.id,
        name: 'FD Renewed',
        amount: 1500.0,
        date: saved.date,
        type: saved.type,
      ));

      expect(provider.investments.length, 1);
      expect(provider.investments.first.name, 'FD Renewed');
      expect(provider.investments.first.amount, 1500.0);
    });

    test('Delete investment', () async {
      await provider.addInvestment(Investment(
        name: 'Stock',
        amount: 200.0,
        date: DateTime(2026, 3, 1),
        type: 'Stocks',
      ));
      final saved = provider.investments.first;

      await provider.deleteInvestment(saved.id!);

      expect(provider.investments, isEmpty);
    });
  });
}
