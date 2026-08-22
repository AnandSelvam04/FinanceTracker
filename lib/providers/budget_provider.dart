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
    // Upsert, so setting a budget for a category+month that already has one
    // replaces it rather than creating a duplicate row.
    await DBService().upsertBudget(budget);
    await fetchBudgets();
  }

  /// Copies the previous month's budgets (category caps and the overall cap)
  /// into [year]/[month], skipping any the target month already has. Returns
  /// how many were copied. Saves re-entering the same caps every month.
  Future<int> copyBudgetsFromPreviousMonth(int year, int month) async {
    final prevYear = month == 1 ? year - 1 : year;
    final prevMonth = month == 1 ? 12 : month - 1;
    final source =
        _budgets.where((b) => b.year == prevYear && b.month == prevMonth);
    var copied = 0;
    for (final b in source) {
      final exists = _budgets.any((x) =>
          x.year == year && x.month == month && x.category == b.category);
      if (exists) continue;
      await DBService().upsertBudget(Budget(
          category: b.category, amount: b.amount, year: year, month: month));
      copied++;
    }
    if (copied > 0) await fetchBudgets();
    return copied;
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

  /// The overall monthly cap (all categories) for [year]/[month] in minor
  /// units, or 0 when none is set.
  int overallBudget(int year, int month) =>
      getBudgetForCategory(year, month, Budget.overallCategory);

  /// The stored overall-budget row for [year]/[month], or null when unset.
  Budget? overallBudgetRow(int year, int month) {
    for (final b in _budgets) {
      if (b.year == year && b.month == month && b.isOverall) return b;
    }
    return null;
  }

  /// Per-category budgets only (excludes the overall cap), for list rendering.
  List<Budget> get categoryBudgets =>
      _budgets.where((b) => !b.isOverall).toList();
}
