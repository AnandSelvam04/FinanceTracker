import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:finance_tracker/utils/merchant_summary.dart';

void main() {
  // Amounts are in minor units (paise).
  Expense e(String description, int amount,
          {String type = DbConstants.txExpense,
          String category = 'Food',
          int day = 1}) =>
      Expense(
        description: description,
        amount: amount,
        date: DateTime(2026, 6, day),
        category: category,
        paymentMode: 'UPI',
        type: type,
      );

  int identity(Expense e) => e.amount;

  test('groups spellings of one merchant and ranks by spend', () {
    final result = topMerchants([
      e('Swiggy', 30000, day: 1),
      e('SWIGGY 88213', 20000, day: 3),
      e('swiggy.', 10000, day: 2),
      e('Uber', 45000, category: 'Transport'),
    ], identity);

    expect(result.map((m) => m.name), ['Swiggy', 'Uber']);
    expect(result.first.total, 60000);
    expect(result.first.count, 3);
    // Newest first.
    expect(result.first.rows.map((r) => r.date.day), [3, 2, 1]);
  });

  test('shows the most used spelling', () {
    final result = topMerchants([
      e('AMAZON PAY', 100),
      e('Amazon Pay', 100),
      e('Amazon Pay', 100),
    ], identity);
    expect(result.single.name, 'Amazon Pay');
  });

  test('skips income, transfers and blank descriptions', () {
    final result = topMerchants([
      e('Employer', 500000, type: DbConstants.txIncome),
      e('To savings', 100000, type: DbConstants.txTransfer),
      e('   ', 5000),
      e('Cafe', 2000),
    ], identity);
    expect(result.map((m) => m.name), ['Cafe']);
  });

  test('refunds come off their merchant; fully refunded ones drop out', () {
    final result = topMerchants([
      e('Myntra', 300000),
      e('Myntra', -100000),
      e('Flipkart', 50000),
      e('Flipkart', -50000),
    ], identity);
    expect(result.single.name, 'Myntra');
    expect(result.single.total, 200000);
    expect(result.single.count, 2);
  });

  test('converts through baseAmountOf and respects the limit', () {
    final rows = [for (var i = 1; i <= 8; i++) e('Shop $i x', i * 100)];
    final result = topMerchants(rows, (r) => r.amount * 2, limit: 3);
    expect(result, hasLength(3));
    expect(result.first.total, 1600);
  });
}
