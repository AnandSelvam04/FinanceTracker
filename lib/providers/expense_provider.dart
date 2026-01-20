import 'package:flutter/material.dart';
import '../models/expense.dart';
import '../services/db_service.dart';

class ExpenseProvider extends ChangeNotifier {
  final List<Expense> _expenses = [];
  final Set<int> _loadedYears = {};

  List<Expense> get expenses => _expenses;

  /// Ensures expenses for the given year are loaded.
  Future<void> ensureYearLoaded(int year) async {
    if (_loadedYears.contains(year)) return;

    final newExpenses = await DBService().getExpensesByYear(year);
    _expenses.addAll(newExpenses);
    // Sort descending by date
    _expenses.sort((a, b) => b.date.compareTo(a.date));
    _loadedYears.add(year);
    notifyListeners();
  }

  /// Reloads expenses for a specific year (e.g., after an update)
  Future<void> _reloadYear(int year) async {
    if (!_loadedYears.contains(year)) return;
    
    // Remove existing expenses for that year
    _expenses.removeWhere((e) => e.date.year == year);
    
    // Fetch fresh data
    final newExpenses = await DBService().getExpensesByYear(year);
    _expenses.addAll(newExpenses);
    _expenses.sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
  }

  /// Reloads all currently loaded years. Useful after a bulk update (e.g. restore).
  Future<void> reloadLoadedYears() async {
    final yearsToReload = _loadedYears.toList();
    _expenses.clear();
    _loadedYears.clear();
    for (final year in yearsToReload) {
      await ensureYearLoaded(year);
    }
  }

  /// Returns the total amount spent in a given year
  double totalForYear(int year) {
    return _expenses
        .where((e) => e.date.year == year)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  /// Returns category totals for a given year
  Map<String, double> categoryTotalsForYear(int year) {
    final map = <String, double>{};
    for (final e in _expenses.where((e) => e.date.year == year)) {
      map[e.category] = (map[e.category] ?? 0) + e.amount;
    }
    return map;
  }

  /// Returns all expenses for a given year
  List<Expense> expensesForYear(int year) =>
      _expenses.where((e) => e.date.year == year).toList();

  Future<void> addExpense(Expense expense) async {
    await DBService().insertExpense(expense);
    // If the year is already loaded, reload it to get the new expense
    // (or we could just add it to the list manually, but reloading is safer for consistency)
    if (_loadedYears.contains(expense.date.year)) {
      await _reloadYear(expense.date.year);
    }
  }

  Future<void> updateExpense(Expense expense) async {
    await DBService().updateExpense(expense);
    if (_loadedYears.contains(expense.date.year)) {
      await _reloadYear(expense.date.year);
    }
  }

  Future<void> deleteExpense(int id) async {
    // We need to find the expense first to know its year, 
    // but since we only delete what we see, it must be in _expenses.
    final index = _expenses.indexWhere((e) => e.id == id);
    if (index != -1) {
      final year = _expenses[index].date.year;
      await DBService().deleteExpense(id);
      await _reloadYear(year);
    }
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
