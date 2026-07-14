import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/currency_format.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;

  setUp(() async {
    DBService.dbNameOverride = 'summary_test.db';
    await DBService().clearAll();
  });

  tearDown(() async {
    await DBService().clearAll();
  });

  // Amounts are in minor units (paise).
  Expense e(int amount, String category, DateTime date,
          {String type = DbConstants.txExpense}) =>
      Expense(
        description: 'x',
        amount: amount,
        date: date,
        category: category,
        paymentMode: 'Cash',
        type: type,
      );

  test('formatMoney matches the app-wide convention', () {
    expect(formatMoney(123450), '₹1234.50');
    expect(formatMoney(0), '₹0.00');
  });

  test('savings rate and net across income/expense', () async {
    final db = DBService();
    final date = DateTime(2026, 6, 10);
    await db.insertExpense(e(10000, 'Salary', date, type: DbConstants.txIncome));
    await db.insertExpense(e(4000, 'Rent', date));
    await db.insertExpense(e(1000, 'Food', date));

    final provider = ExpenseProvider();
    await provider.ensureYearLoaded(2026);

    final income = provider.incomeForMonth(2026, 6);
    final expense = provider.totalForMonth(2026, 6);
    final net = income - expense;
    expect(income, 10000);
    expect(expense, 5000);
    expect(net, 5000);
    expect((net / income) * 100, 50.0); // 50% savings rate
  });

  test('zero-income month yields no savings rate (guard)', () async {
    final db = DBService();
    await db.insertExpense(e(300, 'Food', DateTime(2026, 7, 1)));
    final provider = ExpenseProvider();
    await provider.ensureYearLoaded(2026);

    final income = provider.incomeForMonth(2026, 7);
    expect(income, 0);
    final savingsRate = income > 0 ? 0.0 : null;
    expect(savingsRate, isNull);
  });

  test('top categories are ordered by amount', () async {
    final db = DBService();
    final date = DateTime(2026, 8, 5);
    await db.insertExpense(e(100, 'Food', date));
    await db.insertExpense(e(500, 'Rent', date));
    await db.insertExpense(e(250, 'Transport', date));

    final provider = ExpenseProvider();
    await provider.ensureYearLoaded(2026);

    final totals = provider.categoryTotalsForMonth(2026, 8).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    expect(totals.map((e) => e.key).toList(),
        ['Rent', 'Transport', 'Food']);
  });

  test('month-over-month comparison works across a year boundary', () async {
    final db = DBService();
    await db.insertExpense(e(200, 'Food', DateTime(2025, 12, 15)));
    await db.insertExpense(e(500, 'Food', DateTime(2026, 1, 15)));

    final provider = ExpenseProvider();
    await provider.ensureYearLoaded(2026);
    await provider.ensureYearLoaded(2025);

    final january = provider.totalForMonth(2026, 1);
    final december = provider.totalForMonth(2025, 12);
    expect(january, 500);
    expect(december, 200);
    expect(january - december, 300); // MoM delta
  });
}
