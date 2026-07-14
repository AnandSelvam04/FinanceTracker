import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:finance_tracker/utils/transaction_filter.dart';

void main() {
  Expense e({
    double amount = 100,
    String category = 'Food',
    String type = DbConstants.txExpense,
    int? accountId,
    DateTime? date,
    String description = 'lunch',
  }) =>
      Expense(
        description: description,
        amount: amount,
        date: date ?? DateTime(2026, 6, 15),
        category: category,
        paymentMode: 'Cash',
        type: type,
        accountId: accountId,
      );

  final sample = [
    e(amount: 100, category: 'Food', accountId: 1, date: DateTime(2026, 6, 5)),
    e(amount: 500, category: 'Rent', accountId: 2, date: DateTime(2026, 6, 20)),
    e(
        amount: 3000,
        category: 'Salary',
        type: DbConstants.txIncome,
        accountId: 2,
        date: DateTime(2026, 6, 1),
        description: 'June pay'),
    e(amount: 50, category: 'Food', accountId: 1, date: DateTime(2026, 7, 2)),
  ];

  test('year + month narrows to the period', () {
    final r = const TransactionFilter(year: 2026, month: 6).apply(sample);
    expect(r.length, 3);
  });

  test('category filter', () {
    final r =
        const TransactionFilter(year: 2026, month: null, category: 'Food')
            .apply(sample);
    expect(r.length, 2);
    expect(r.every((x) => x.category == 'Food'), isTrue);
  });

  test('account filter', () {
    final r = const TransactionFilter(year: 2026, month: 6, accountId: 2)
        .apply(sample);
    expect(r.length, 2);
  });

  test('amount range filter', () {
    final r = const TransactionFilter(
            year: 2026, month: null, minAmount: 100, maxAmount: 1000)
        .apply(sample);
    expect(r.map((x) => x.amount).toList()..sort(), [100, 500]);
  });

  test('type filter', () {
    final r = const TransactionFilter(
            year: 2026, month: 6, type: DbConstants.txIncome)
        .apply(sample);
    expect(r.single.category, 'Salary');
  });

  test('custom date range overrides year/month', () {
    final r = TransactionFilter(
      year: 1999, // ignored because a range is set
      month: 1,
      startDate: DateTime(2026, 6, 10),
      endDate: DateTime(2026, 7, 5),
    ).apply(sample);
    // June 20 (Rent) and July 2 (Food) fall in range.
    expect(r.length, 2);
    expect(r.map((x) => x.category).toSet(), {'Rent', 'Food'});
  });

  test('search matches description or category', () {
    final r = const TransactionFilter(
            year: 2026, month: 6, searchQuery: 'pay')
        .apply(sample);
    expect(r.single.category, 'Salary');
  });

  test('combined filters intersect', () {
    final r = const TransactionFilter(
      year: 2026,
      month: 6,
      category: 'Food',
      accountId: 1,
      maxAmount: 200,
    ).apply(sample);
    expect(r.single.amount, 100);
  });
}
