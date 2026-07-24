import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/investment.dart';
import 'package:finance_tracker/providers/investment_provider.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  // Isolate this file's database so concurrently running test files
  // can't clear each other's data (they all share one ffi process).
  DBService.dbNameOverride = 'investment_provider_test.db';

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
        amount: 500000, // 5000.00
        date: DateTime(2026, 1, 15),
        type: 'Mutual Funds',
      ));

      expect(provider.investments.length, 1);
      expect(provider.investments.first.name, 'Index Fund');
      expect(provider.investments.first.amount, 500000);
    });

    test('Update investment', () async {
      await provider.addInvestment(Investment(
        name: 'FD',
        amount: 100000,
        date: DateTime(2026, 2, 1),
        type: 'FD',
      ));
      final saved = provider.investments.first;

      await provider.updateInvestment(Investment(
        id: saved.id,
        name: 'FD Renewed',
        amount: 150000,
        date: saved.date,
        type: saved.type,
      ));

      expect(provider.investments.length, 1);
      expect(provider.investments.first.name, 'FD Renewed');
      expect(provider.investments.first.amount, 150000);
    });

    test('Delete investment', () async {
      await provider.addInvestment(Investment(
        name: 'Stock',
        amount: 20000,
        date: DateTime(2026, 3, 1),
        type: 'Stocks',
      ));
      final saved = provider.investments.first;

      await provider.deleteInvestment(saved.id!);

      expect(provider.investments, isEmpty);
    });

    test('Multiple contributions of a type accumulate into its total',
        () async {
      await provider.addInvestment(Investment(
        name: 'Silver Jun',
        amount: 100000,
        date: DateTime(2026, 6, 10),
        type: 'Silver',
      ));
      await provider.addInvestment(Investment(
        name: 'Silver Jul',
        amount: 250000,
        date: DateTime(2026, 7, 5),
        type: 'Silver',
      ));
      await provider.addInvestment(Investment(
        name: 'Gold Jul',
        amount: 500000,
        date: DateTime(2026, 7, 5),
        type: 'Gold',
      ));

      expect(provider.totalInvested, 850000);

      final totals = provider.totalsByType();
      // Ordered largest first: Gold (5000) then Silver (3500).
      expect(totals.first.key, 'Gold');
      expect(totals.first.value, 500000);
      expect(totals[1].key, 'Silver');
      expect(totals[1].value, 350000);

      expect(provider.ofType('Silver').length, 2);
    });

    test('monthlyBreakdown groups a type by calendar month, newest first',
        () async {
      await provider.addInvestment(Investment(
        name: 'Silver A',
        amount: 100000,
        date: DateTime(2026, 6, 10),
        type: 'Silver',
      ));
      await provider.addInvestment(Investment(
        name: 'Silver B',
        amount: 150000,
        date: DateTime(2026, 7, 5),
        type: 'Silver',
      ));
      await provider.addInvestment(Investment(
        name: 'Silver C',
        amount: 50000,
        date: DateTime(2026, 7, 20),
        type: 'Silver',
      ));

      final breakdown = provider.monthlyBreakdown('Silver');
      expect(breakdown.keys.toList(), ['2026-07', '2026-06']);
      expect(breakdown['2026-07']!.length, 2);
      expect(breakdown['2026-06']!.length, 1);

      final julyTotal =
          breakdown['2026-07']!.fold<int>(0, (s, i) => s + i.amount);
      expect(julyTotal, 200000);
    });
  });
}
