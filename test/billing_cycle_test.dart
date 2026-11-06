import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/utils/billing_cycle.dart';

void main() {
  group('computeCreditCardCycle', () {
    test('due day after statement day is in the same month', () {
      final c = computeCreditCardCycle(
          statementDay: 5, dueDay: 25, now: DateTime(2026, 3, 10));
      expect(c.statementDate, DateTime(2026, 3, 5));
      // The statement day is billed: cycle 6 Feb – 5 Mar.
      expect(c.billedCycleStart, DateTime(2026, 2, 6));
      expect(c.billedUntil, DateTime(2026, 3, 6));
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
      expect(c.billedCycleStart, DateTime(2026, 1, 1));
      expect(c.billedUntil, DateTime(2026, 2, 1));
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
        start == DateTime(2026, 2, 6) ? 50000 : 12000;

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

    test('a statement paid in full produces no reminder', () {
      final r = creditCardReminders(
        accounts: [card()],
        now: DateTime(2026, 3, 20),
        spendInRange: spend, // 50,000 billed
        paidInRange: (_, start, __) =>
            start == DateTime(2026, 3, 5) ? 50000 : 0,
      );
      expect(r, isEmpty);
    });

    test('a part payment leaves the rest due', () {
      final r = creditCardReminders(
        accounts: [card()],
        now: DateTime(2026, 3, 20),
        spendInRange: spend,
        paidInRange: (_, start, __) =>
            start == DateTime(2026, 3, 5) ? 20000 : 0,
      );
      expect(r.single.amountDue, 30000);
      expect(r.single.statementAmount, 50000);
    });
  });

  group('statement day is billed', () {
    // A purchase on the statement date itself, and one the day after.
    final purchases = {
      DateTime(2026, 3, 5): 30000,
      DateTime(2026, 3, 6): 7000,
    };
    int spend(int id, DateTime start, DateTime end) => purchases.entries
        .where((e) => !e.key.isBefore(start) && e.key.isBefore(end))
        .fold(0, (sum, e) => sum + e.value);

    test('a purchase on the statement day is on that statement', () {
      final r = creditCardReminders(
        accounts: [
          Account(
              id: 1,
              name: 'Visa',
              type: 'credit_card',
              statementDay: 5,
              dueDay: 25),
        ],
        now: DateTime(2026, 3, 20),
        spendInRange: spend,
      );
      expect(r.single.statementAmount, 30000);
      expect(r.single.currentCycleSpend, 7000);
    });
  });

  group('overdue previous statement', () {
    // Statement on the 1st, due on the 28th: the next statement arrives
    // only four days after the due date.
    final card = Account(
        id: 1, name: 'Visa', type: 'credit_card', statementDay: 1, dueDay: 28);
    // 40,000 billed on the 1 Mar statement (cycle 2 Feb – 1 Mar), 9,000 on 1 Apr.
    int spend(int id, DateTime start, DateTime end) {
      if (start == DateTime(2026, 2, 2)) return 40000;
      if (start == DateTime(2026, 3, 2)) return 9000;
      return 0;
    }

    test('stays on the list after the next statement is generated', () {
      final r = creditCardReminders(
        accounts: [card],
        now: DateTime(2026, 4, 2), // Mar 28 due date was 5 days ago
        spendInRange: spend,
      );
      expect(r.single.dueDate, DateTime(2026, 3, 28));
      expect(r.single.isOverdue, isTrue);
      expect(r.single.daysUntilDue, -5);
      expect(r.single.statementAmount, 40000);
    });

    test('goes once it is paid, leaving the new statement', () {
      final r = creditCardReminders(
        accounts: [card],
        now: DateTime(2026, 4, 2),
        spendInRange: spend,
        paidInRange: (_, start, __) =>
            start == DateTime(2026, 3, 1) ? 40000 : 0,
        withinDays: 45,
      );
      expect(r.single.dueDate, DateTime(2026, 4, 28));
      expect(r.single.statementAmount, 9000);
    });

    test('is dropped once past the overdue grace', () {
      final r = creditCardReminders(
        accounts: [card],
        now: DateTime(2026, 4, 2),
        spendInRange: spend,
        overdueGrace: 3,
        withinDays: 45,
      );
      expect(r.single.dueDate, DateTime(2026, 4, 28));
    });
  });
}
