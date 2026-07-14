import 'package:flutter/material.dart';
import '../models/budget.dart';
import '../services/db_service.dart';

class BudgetProvider extends ChangeNotifier {
  List<Budget> _budgets = [];

  List<Budget> get budgets => _budgets;

  Future<void> fetchBudgets() async {
    _budgets = await DBService().getBudgets();
    notifyListeners();
  }

  Future<void> addBudget(Budget budget) async {
    await DBService().insertBudget(budget);
    await fetchBudgets();
  }

  Future<void> updateBudget(Budget budget) async {
    await DBService().updateBudget(budget);
    await fetchBudgets();
  }

  Future<void> deleteBudget(int id) async {
    await DBService().deleteBudget(id);
    await fetchBudgets();
  }

  int getBudgetForCategory(int year, int month, String category) {
    final budget = _budgets.firstWhere(
      (b) => b.year == year && b.month == month && b.category == category,
      orElse: () =>
          Budget(category: category, amount: 0, year: year, month: month),
    );
    return budget.amount;
  }
}
