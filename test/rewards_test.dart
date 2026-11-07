import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/services/sms_import.dart';
import 'package:finance_tracker/utils/credit_card_summary.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;

  group('rewardPointsOf', () {
    test('a balance, with the card', () {
      final r = SmsImport.rewardPointsOf('Rs 500 spent on Card XX1234. '
          'Reward Points balance: 12,345');
      expect(r!.points, 12345);
      expect(r.last4, '1234');
      expect(
          SmsImport.rewardPointsOf('Your card x9876 reward point bal is 4,560')!
              .points,
          4560);
    });

    test('points earned are not a balance', () {
      expect(
          SmsImport.rewardPointsOf('You earned 50 reward points on card 1234'),
          isNull);
    });
  });

  group('rewardEstimate', () {
    final now = DateTime(2026, 11, 20);
    int spend(DateTime from, DateTime to) =>
        from == DateTime(2026, 11, 2) ? 2500000 : 1000000; // 25,000 / 10,000

    test('balance set by hand, plus what was earned since', () {
      final card = Account(
          id: 1,
          name: 'Visa',
          type: 'credit_card',
          rewardPoints: 10000,
          rewardAsOf: DateTime(2026, 11, 1),
          rewardRate: 4,
          pointValue: 0.25);
      final e = rewardEstimate(card,
          now: now, periodStart: DateTime(2026, 11, 6), spendBetween: spend)!;
      expect(e.earned, 1000); // 25,000 at 4 per ₹100
      expect(e.points, 11000);
      expect(e.value, 275000); // ₹2,750
      expect(e.fromSms, isFalse);
    });

    test('a newer SMS balance replaces the one set by hand', () {
      final card = Account(
          id: 1,
          name: 'Visa',
          type: 'credit_card',
          rewardPoints: 10000,
          rewardAsOf: DateTime(2026, 10, 1),
          rewardRate: 4);
      final e = rewardEstimate(card,
          now: now,
          periodStart: DateTime(2026, 11, 6),
          spendBetween: spend,
          smsReading: (points: 12000, at: DateTime(2026, 11, 1, 18)))!;
      expect(e.baseline, 12000);
      expect(e.points, 13000);
      expect(e.fromSms, isTrue);
    });

    test('only an earn rate: what this period earned', () {
      final card =
          Account(id: 1, name: 'Visa', type: 'credit_card', rewardRate: 2);
      final e = rewardEstimate(card,
          now: now, periodStart: DateTime(2026, 11, 6), spendBetween: spend)!;
      expect(e.earnedOnly, isTrue);
      expect(e.points, 200);
    });

    test('nothing set, nothing shown', () {
      expect(
          rewardEstimate(Account(id: 1, name: 'Visa', type: 'credit_card'),
              now: now, periodStart: now, spendBetween: spend),
          isNull);
    });
  });

  test('reward fields are saved and read back', () async {
    DBService.dbNameOverride = 'rewards_test.db';
    await DBService().clearAll();
    final id = await DBService().insertAccount(Account(
        name: 'Visa',
        type: 'credit_card',
        rewardPoints: 500,
        rewardAsOf: DateTime(2026, 11, 1),
        rewardRate: 3.3,
        pointValue: 0.5));
    final a = (await DBService().getAccounts()).firstWhere((x) => x.id == id);
    expect(a.rewardPoints, 500);
    expect(a.rewardAsOf, DateTime(2026, 11, 1));
    expect(a.rewardRate, 3.3);
    expect(a.pointValue, 0.5);
    // Kept through a copy (the shared limit and balance-match edits use it).
    expect(a.copyWith(openingBalance: 5).rewardRate, 3.3);
    await DBService().clearAll();
  });
}
