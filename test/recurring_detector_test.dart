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
    expect(RecurringDetector.looksMonthly('', 19900, history, asOf: now),
        isFalse);
    expect(RecurringDetector.looksMonthly('X', 0, history, asOf: now), isFalse);
  });
}
