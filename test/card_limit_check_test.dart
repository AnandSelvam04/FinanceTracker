import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/services/card_limit_readings.dart';
import 'package:finance_tracker/services/sms_import.dart';
import 'package:finance_tracker/utils/credit_card_summary.dart';

void main() {
  group('availableLimitOf', () {
    test('HDFC: "Avl Lmt: Rs 1,85,000.00" with the card digits', () {
      final r = SmsImport.availableLimitOf(
          'Rs.499 spent on HDFC Bank Card x1234 at AMAZON on '
          '2026-11-06:10:30:00. Avl Lmt: Rs 1,85,000.00. Not you? Call');
      expect(r!.amount, 18500000);
      expect(r.last4, '1234');
    });

    test('other wordings', () {
      expect(
          SmsImport.availableLimitOf('INR 2,000 spent on card ending 5678. '
                  'Available limit is INR 1,23,456.78')!
              .amount,
          12345678);
      expect(
          SmsImport.availableLimitOf(
                  'Txn of Rs 50 on Card XX9012. Avbl Cr Lmt INR 50,000')!
              .amount,
          5000000);
      expect(
          SmsImport.availableLimitOf(
                  'Card XX9012 used. Available Credit Limit: Rs.12,345')!
              .amount,
          1234500);
    });

    test('a balance is not a limit', () {
      expect(
          SmsImport.availableLimitOf(
              'Rs 500 debited from A/c XX4821. Avl Bal Rs 12,340'),
          isNull);
      // The transaction amount is still what the parser books.
      final parsed = SmsImport.parse(
          sender: 'VM-HDFCBK',
          body: 'Rs.499 spent on HDFC Bank Card x1234 at AMAZON. '
              'Avl Lmt: Rs 1,85,000.00',
          receivedAt: DateTime(2026, 11, 6));
      expect(parsed!.amount, 49900);
    });
  });

  group('CardLimitReadings', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('keeps the newest reading per card', () async {
      await CardLimitReadings.record([
        LimitReading(last4: '1234', amount: 100, at: DateTime(2026, 11, 5)),
        LimitReading(last4: '1234', amount: 200, at: DateTime(2026, 11, 6)),
        LimitReading(last4: '5678', amount: 300, at: DateTime(2026, 11, 1)),
      ]);
      await CardLimitReadings.record([
        LimitReading(last4: '1234', amount: 50, at: DateTime(2026, 11, 2)),
      ]);
      final all = await CardLimitReadings.load();
      expect(all['1234']!.amount, 200);
      expect(CardLimitReadings.forCard(all, '5678')!.amount, 300);
      expect(CardLimitReadings.forCard(all, '0000'), isNull);
    });
  });

  group('bankLimitCheck', () {
    final now = DateTime(2026, 11, 7, 12);
    final visa = Account(
        id: 1,
        name: 'Visa',
        type: 'credit_card',
        creditLimit: 20000000,
        last4: '1111');
    final rupay = Account(
        id: 2,
        name: 'RuPay',
        type: 'credit_card',
        sharedLimitWith: 1,
        last4: '2222');

    CreditCardSummary summaryFor(
            Account a, List<Account> all, Map<int, int> balances) =>
        creditCardSummaries(
          accounts: all,
          now: now,
          spendInRange: (_, __, ___) => 0,
          paidInRange: (_, __, ___) => 0,
          balanceOf: (x) => balances[x.id],
        ).firstWhere((s) => s.account.id == a.id);

    test('agrees when the bank and the app agree', () {
      final s = summaryFor(visa, [visa, rupay], {1: -1000000, 2: -500000});
      final c = bankLimitCheck(
        summary: s,
        readingFor: (card) => card.id == 2
            ? (amount: 18500000, at: DateTime(2026, 11, 7, 9))
            : null,
        now: now,
        spendInRange: (_, __, ___) => 0,
        paidInRange: (_, __, ___) => 0,
      )!;
      expect(c.card.id, 2);
      expect(c.appAvailable, 18500000);
      expect(c.matches, isTrue);
    });

    test('brings an older reading up to today before comparing', () {
      // The bank said 1,90,000 on the 5th; 5,000 went on the Visa since.
      final s = summaryFor(visa, [visa, rupay], {1: -1000000, 2: -500000});
      final c = bankLimitCheck(
        summary: s,
        readingFor: (card) => card.id == 1
            ? (amount: 19000000, at: DateTime(2026, 11, 5, 20))
            : null,
        now: now,
        spendInRange: (id, from, to) =>
            id == 1 && from == DateTime(2026, 11, 6) ? 500000 : 0,
        paidInRange: (_, __, ___) => 0,
      )!;
      expect(c.bankAvailable, 18500000);
      expect(c.matches, isTrue);
    });

    test('flags a missing purchase', () {
      final s = summaryFor(visa, [visa], {1: -1000000});
      final c = bankLimitCheck(
        summary: s,
        readingFor: (_) => (amount: 18000000, at: DateTime(2026, 11, 7, 9)),
        now: now,
        spendInRange: (_, __, ___) => 0,
        paidInRange: (_, __, ___) => 0,
      )!;
      expect(c.matches, isFalse);
      expect(c.difference, 1000000);
    });

    test('ignores stale readings and cards without a limit', () {
      final s = summaryFor(visa, [visa], {1: 0});
      expect(
          bankLimitCheck(
            summary: s,
            readingFor: (_) => (amount: 1, at: DateTime(2026, 8, 1)),
            now: now,
            spendInRange: (_, __, ___) => 0,
            paidInRange: (_, __, ___) => 0,
          ),
          isNull);
      final plain = Account(id: 3, name: 'Amex', type: 'credit_card');
      expect(
          bankLimitCheck(
            summary: summaryFor(plain, [plain], {3: 0}),
            readingFor: (_) => (amount: 1, at: now),
            now: now,
            spendInRange: (_, __, ___) => 0,
            paidInRange: (_, __, ___) => 0,
          ),
          isNull);
    });
  });
}
