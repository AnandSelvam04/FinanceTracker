import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/utils/billing_cycle.dart';

void main() {
  group('computeCreditCardCycle', () {
    test('due day after statement day is in the same month', () {
      final c = computeCreditCardCycle(
          statementDay: 5, dueDay: 25, now: DateTime(2026, 3, 10));
      expect(c.statementDate, DateTime(2026, 3, 5));
      expect(c.billedCycleStart, DateTime(2026, 2, 5));
      expect(c.nextStatementDate, DateTime(2026, 4, 5));
      expect(c.dueDate, DateTime(2026, 3, 25));
      expect(c.daysUntilDue, 15);
    });

    test('due day before statement day rolls to the next month', () {
      final c = computeCreditCardCycle(
          statementDay: 25, dueDay: 10, now: DateTime(2026, 3, 27));
      expect(c.statementDate, DateTime(2026, 3, 25));
      expect(c.dueDate, DateTime(2026, 4, 10));
      expect(c.daysUntilDue, 14);
    });

    test('before this month\'s statement uses last month\'s', () {
      final c = computeCreditCardCycle(
          statementDay: 25, dueDay: 10, now: DateTime(2026, 3, 5));
      expect(c.statementDate, DateTime(2026, 2, 25));
      expect(c.dueDate, DateTime(2026, 3, 10));
      expect(c.daysUntilDue, 5);
    });

    test('clamps a 31 statement day into short months', () {
      final c = computeCreditCardCycle(
          statementDay: 31, dueDay: 20, now: DateTime(2026, 2, 15));
      // Feb has no 31st; last statement was Jan 31.
      expect(c.statementDate, DateTime(2026, 1, 31));
      expect(c.billedCycleStart, DateTime(2025, 12, 31));
      expect(c.nextStatementDate, DateTime(2026, 2, 28));
    });
  });

  group('creditCardReminders', () {
    Account card({int? statementDay = 5, int? dueDay = 25, String? currency}) =>
        Account(
          id: 1,
          name: 'Visa',
          type: 'credit_card',
          statementDay: statementDay,
          dueDay: dueDay,
          currency: currency,
        );

    int spend(int id, DateTime start, DateTime end) =>
        start == DateTime(2026, 2, 5) ? 50000 : 12000;

    test('reminds with the statement amount when due is near', () {
      final r = creditCardReminders(
        accounts: [card()],
        now: DateTime(2026, 3, 20), // due Mar 25 → 5 days
        spendInRange: spend,
      );
      expect(r, hasLength(1));
      expect(r.first.accountId, 1);
      expect(r.first.statementAmount, 50000);
      expect(r.first.currentCycleSpend, 12000);
      expect(r.first.daysUntilDue, 5);
    });

    test('no reminder while the due date is still far off', () {
      final r = creditCardReminders(
        accounts: [card()],
        now: DateTime(2026, 3, 10), // due in 15 days, default window 7
        spendInRange: spend,
      );
      expect(r, isEmpty);
    });

    test('no reminder when nothing was billed', () {
      final r = creditCardReminders(
        accounts: [card()],
        now: DateTime(2026, 3, 20),
        spendInRange: (_, __, ___) => 0,
      );
      expect(r, isEmpty);
    });

    test('skips cards without a billing cycle and non-card accounts', () {
      final r = creditCardReminders(
        accounts: [
          card(statementDay: null, dueDay: null),
          Account(id: 2, name: 'Bank', type: 'bank'),
        ],
        now: DateTime(2026, 3, 20),
        spendInRange: spend,
      );
      expect(r, isEmpty);
    });
  });
}
