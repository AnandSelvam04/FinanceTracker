import 'package:flutter_test/flutter_test.dart';

import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:finance_tracker/utils/year_review.dart';

void main() {
  Expense e(String description, int amount, DateTime date,
          {String type = DbConstants.txExpense}) =>
      Expense(
          description: description,
          amount: amount,
          date: date,
          category: 'Food',
          paymentMode: 'UPI',
          type: type);

  final rows = [
    e('Rent', 2000000, DateTime(2025, 1, 5)),
    e('Laptop', 6000000, DateTime(2025, 3, 9)),
    e('Laptop refund', -1000000, DateTime(2025, 3, 20)),
    e('Lunch', 30000, DateTime(2025, 3, 9)),
    e('Groceries', 400000, DateTime(2025, 7, 1)),
    e('Salary', 9000000, DateTime(2025, 1, 1), type: DbConstants.txIncome),
    e('Salary', 9000000, DateTime(2025, 3, 1), type: DbConstants.txIncome),
    e('Card bill', 500000, DateTime(2025, 3, 2), type: DbConstants.txTransfer),
    // Another year: ignored.
    e('Old', 99999900, DateTime(2024, 6, 6)),
  ];

  YearReview review(int year, DateTime now) => YearReview.from(rows,
      year: year, baseAmountOf: (e) => e.amount, now: now);

  test('sums each month, netting refunds and leaving transfers out', () {
    final r = review(2025, DateTime(2026, 2, 1));
    expect(r.monthlyExpense[0], 2000000);
    expect(r.monthlyExpense[2], 5030000);
    expect(r.monthlyExpense[6], 400000);
    expect(r.monthlyIncome[0], 9000000);
    expect(r.totalExpense, 7430000);
    expect(r.totalIncome, 18000000);
    expect(r.isEmpty, isFalse);
  });

  test('a past year averages over twelve months', () {
    final r = review(2025, DateTime(2026, 2, 1));
    expect(r.monthsElapsed, 12);
    expect(r.averageMonthlyExpense, (7430000 / 12).round());
    expect(r.highestMonth, 3);
    expect(r.lowestMonth, 7);
    // Jan kept 70,000; Mar kept 39,700.
    expect(r.bestSavingMonth, 1);
    expect(r.biggest!.description, 'Laptop');
    // 365 days, spending on 5 Jan, 9 Mar and 1 Jul.
    expect(r.noSpendDays, 362);
  });

  test('the current year only counts the months and days so far', () {
    final r = review(2025, DateTime(2025, 3, 31));
    expect(r.monthsElapsed, 3);
    expect(r.averageMonthlyExpense, (7430000 / 3).round());
    // July hasn't happened yet, so it can't be the lowest month.
    expect(r.lowestMonth, 1);
    // 31 + 28 + 31 days, two of them with spending.
    expect(r.noSpendDays, 88);
  });

  test('a year with nothing in it is empty and has no highlights', () {
    final past = review(2023, DateTime(2026, 1, 1));
    expect(past.isEmpty, isTrue);
    expect(past.highestMonth, isNull);
    expect(past.lowestMonth, isNull);
    expect(past.bestSavingMonth, isNull);
    expect(past.biggest, isNull);

    final future = review(2030, DateTime(2026, 1, 1));
    expect(future.monthsElapsed, 0);
    expect(future.averageMonthlyExpense, 0);
    expect(future.noSpendDays, 0);
  });

  test('one month of spending has a highest month but no lowest', () {
    final r = YearReview.from([e('Only', 100, DateTime(2025, 5, 5))],
        year: 2025, baseAmountOf: (e) => e.amount, now: DateTime(2026, 1, 1));
    expect(r.highestMonth, 5);
    expect(r.lowestMonth, isNull);
  });
}
