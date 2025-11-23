import 'package:flutter/material.dart';
import '../models/expense.dart';
import '../services/db_service.dart';

class ExpenseProvider extends ChangeNotifier {
  List<Expense> _expenses = [];

  List<Expense> get expenses => _expenses;

  Future<void> fetchExpenses() async {
    _expenses = await DBService().getExpenses();
    notifyListeners();
  }

  Future<void> addExpense(Expense expense) async {
    await DBService().insertExpense(expense);
    await fetchExpenses();
  }

  Future<void> updateExpense(Expense expense) async {
    await DBService().updateExpense(expense);
    await fetchExpenses();
  }

  Future<void> deleteExpense(int id) async {
    await DBService().deleteExpense(id);
    await fetchExpenses();
  }

  /// Returns expenses for a given month and year
  List<Expense> expensesForMonth(int year, int month) {
    return _expenses
        .where((e) => e.date.year == year && e.date.month == month)
        .toList();
  }

  /// Returns the total amount spent in a given month and year
  double totalForMonth(int year, int month) {
    return expensesForMonth(year, month).fold(0.0, (sum, e) => sum + e.amount);
  }

  /// Returns a map of category to total for a given month and year
  Map<String, double> categoryTotalsForMonth(int year, int month) {
    final map = <String, double>{};
    for (final e in expensesForMonth(year, month)) {
      map[e.category] = (map[e.category] ?? 0) + e.amount;
    }
    return map;
  }
}
