import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/services/recurring_detector.dart';
import 'package:finance_tracker/utils/db_constants.dart';

/// The rule that decides whether an SMS charge is offered as a recurring rule.
void main() {
  final now = DateTime(2025, 8, 15);

  Expense spend(String desc, int amount, DateTime date,
          {String type = DbConstants.txExpense}) =>
      Expense(
        description: desc,
        amount: amount,
        date: date,
        category: 'Bills',
        paymentMode: 'Other',
        type: type,
      );

  test('flags a charge seen in two prior months', () {
    final history = [
      spend('NETFLIX', 19900, DateTime(2025, 6, 15)),
      spend('NETFLIX', 19900, DateTime(2025, 7, 15)),
    ];
    expect(RecurringDetector.looksMonthly('NETFLIX', 19900, history, asOf: now),
        isTrue);
  });

  test('one prior month is not enough', () {
    final history = [spend('NETFLIX', 19900, DateTime(2025, 7, 15))];
    expect(RecurringDetector.looksMonthly('NETFLIX', 19900, history, asOf: now),
        isFalse);
  });

  test('the current month does not vote for itself', () {
    final history = [
      spend('NETFLIX', 19900, DateTime(2025, 8, 1)),
      spend('NETFLIX', 19900, DateTime(2025, 8, 2)),
    ];
    expect(RecurringDetector.looksMonthly('NETFLIX', 19900, history, asOf: now),
        isFalse);
  });

  test('a small amount drift still matches', () {
    final history = [
      spend('SPOTIFY', 11900, DateTime(2025, 6, 10)),
      spend('SPOTIFY', 12000, DateTime(2025, 7, 10)),
    ];
    expect(RecurringDetector.looksMonthly('SPOTIFY', 11900, history, asOf: now),
        isTrue);
  });

  test('a very different amount does not match', () {
    final history = [
      spend('AMAZON', 500000, DateTime(2025, 6, 10)),
      spend('AMAZON', 20000, DateTime(2025, 7, 10)),
    ];
    expect(RecurringDetector.looksMonthly('AMAZON', 20000, history, asOf: now),
        isFalse);
  });

  test('income is never treated as a subscription', () {
    final history = [
      spend('SALARY', 4500000, DateTime(2025, 6, 1),
          type: DbConstants.txIncome),
      spend('SALARY', 4500000, DateTime(2025, 7, 1),
          type: DbConstants.txIncome),
    ];
    expect(
        RecurringDetector.looksMonthly('SALARY', 4500000, history, asOf: now),
        isFalse);
  });

  test('the merchant match is case-insensitive', () {
    final history = [
      spend('netflix', 19900, DateTime(2025, 6, 15)),
      spend('Netflix', 19900, DateTime(2025, 7, 15)),
    ];
    expect(RecurringDetector.looksMonthly('NETFLIX', 19900, history, asOf: now),
        isTrue);
  });

  test('an empty description or non-positive amount is never recurring', () {
    final history = [
      spend('', 19900, DateTime(2025, 6, 15)),
      spend('', 19900, DateTime(2025, 7, 15)),
    ];
    expect(
        RecurringDetector.looksMonthly('', 19900, history, asOf: now), isFalse);
    expect(RecurringDetector.looksMonthly('X', 0, history, asOf: now), isFalse);
  });

  group('suggestions', () {
    final asOf = DateTime(2026, 9, 20);

    test('offers a payee charged about the same in three recent months', () {
      final found = RecurringDetector.suggestions([
        spend('Netflix', 64900, DateTime(2026, 7, 5)),
        spend('Netflix', 64900, DateTime(2026, 8, 5)),
        spend('NETFLIX ', 64900, DateTime(2026, 9, 5)),
        spend('Groceries', 120000, DateTime(2026, 9, 6)),
      ], asOf: asOf);
      expect(found.single.description, 'NETFLIX');
      expect(found.single.amount, 64900);
      expect(found.single.months, 3);
      expect(found.single.nextDue(asOf), DateTime(2026, 10, 5));
    });

    test('leaves out a payee that already has a rule, or was dismissed', () {
      final rows = [
        for (final m in [7, 8, 9]) spend('Gym', 150000, DateTime(2026, m, 1)),
      ];
      expect(RecurringDetector.suggestions(rows, asOf: asOf), hasLength(1));
      expect(RecurringDetector.suggestions(rows, known: ['gym'], asOf: asOf),
          isEmpty);
    });

    test('leaves out one that stopped, and two months is not a pattern', () {
      expect(
          RecurringDetector.suggestions([
            for (final m in [4, 5, 6])
              spend('Old app', 9900, DateTime(2026, m, 3)),
          ], asOf: asOf),
          isEmpty);
      expect(
          RecurringDetector.suggestions([
            for (final m in [8, 9])
              spend('New app', 9900, DateTime(2026, m, 3)),
          ], asOf: asOf),
          isEmpty);
    });

    test('the next due date keeps the day, clamped to short months', () {
      final s = RecurringDetector.suggestions([
        for (final m in [8, 10, 12])
          spend('Rent', 2000000, DateTime(2026, m, 31)),
      ], asOf: DateTime(2027, 1, 10))
          .single;
      expect(s.nextDue(DateTime(2027, 1, 10)), DateTime(2027, 1, 31));
      expect(s.nextDue(DateTime(2027, 2, 1)), DateTime(2027, 2, 28));
    });
  });
}
