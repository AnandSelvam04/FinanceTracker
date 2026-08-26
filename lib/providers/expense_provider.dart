import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import '../models/expense.dart';
import '../services/db_service.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';

class ExpenseProvider extends ChangeNotifier {
  final List<Expense> _expenses = [];
  final Set<int> _loadedYears = {};

  /// Memoized results of the per-period aggregates (totals, category maps,
  /// spend-by-account). Each one is an O(n) scan over every loaded row, and the
  /// dashboard, budgets, cashflow, monthly-summary, and category-trends screens
  /// all ask for the same figures — often more than once — on every rebuild.
  ///
  /// The cache is cleared in [notifyListeners], which every path that changes
  /// the underlying data (a load, an add/update/delete, a restore, an exchange-
  /// rate change) already calls. Clearing there rather than at each mutation
  /// site means a new aggregate can never be added and silently miss an
  /// invalidation. Keys are namespaced per method + arguments.
  final Map<String, Object> _aggCache = {};

  T _memo<T extends Object>(String key, T Function() compute) =>
      _aggCache.putIfAbsent(key, compute) as T;

  @override
  void notifyListeners() {
    _aggCache.clear();
    super.notifyListeners();
  }

  /// Exchange rate per account id (base-currency units per 1 unit of the
  /// account's currency), mirrored from `AccountProvider` by the
  /// `ChangeNotifierProxyProvider` in main.dart.
  ///
  /// Every row's amount is stored in *its source account's* currency, so any
  /// total shown in the base currency has to convert. Without this the
  /// dashboard counted a $100 expense as ₹100 and labelled it with the base
  /// symbol, disagreeing with the net-worth card right above it.
  Map<int, double> _ratesByAccount = const {};

  /// All loaded transaction rows (expenses, income, and transfers).
  List<Expense> get expenses => _expenses;

  int _pendingLoads = 0;

  /// Whether a year is currently being fetched.
  ///
  /// Without this, every list and the dashboard rendered their "No expenses
  /// found" empty state for the first few frames of a cold start, which reads
  /// as data loss on a large database.
  bool get isLoading => _pendingLoads > 0;

  /// Runs [work] with [isLoading] set, so the UI can show a spinner instead of
  /// an empty state. Nested/concurrent loads are counted, not toggled.
  Future<T> _tracked<T>(Future<T> Function() work) async {
    if (_pendingLoads++ == 0) notifyListeners();
    try {
      return await work();
    } finally {
      if (--_pendingLoads == 0) notifyListeners();
    }
  }

  /// Mirrors the current account exchange rates. Safe to call on every
  /// account change; only notifies when a rate actually moved.
  void syncAccountRates(Map<int, double> rates) {
    if (mapEquals(_ratesByAccount, rates)) return;
    _ratesByAccount = Map.unmodifiable(rates);
    notifyListeners();
  }

  /// [e]'s amount converted to base-currency minor units.
  ///
  /// Rows with no account, or an account whose rate we haven't loaded, fall
  /// back to 1.0 — the same value a single-currency setup would use.
  int baseAmountOf(Expense e) {
    final rate = _ratesByAccount[e.accountId] ?? 1.0;
    return rate == 1.0 ? e.amount : toBaseMinor(e.amount, rate);
  }

  int _sumBase(Iterable<Expense> rows) =>
      rows.fold(0, (sum, e) => sum + baseAmountOf(e));

  Map<String, int> _categoryTotals(Iterable<Expense> rows) {
    final map = <String, int>{};
    for (final e in rows) {
      map[e.category] = (map[e.category] ?? 0) + baseAmountOf(e);
    }
    return map;
  }

  /// Ensures expenses for the given year are loaded.
  Future<void> ensureYearLoaded(int year) async {
    if (_loadedYears.contains(year)) return;

    await _tracked(() async {
      final newExpenses = await DBService().getExpensesByYear(year);
      _expenses.addAll(newExpenses);
      // Sort descending by date
      _expenses.sort((a, b) => b.date.compareTo(a.date));
      _loadedYears.add(year);
    });
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

  /// Ensures every year in [years] is loaded (e.g. for a custom date range).
  Future<void> ensureYearsLoaded(Iterable<int> years) async {
    for (final year in years) {
      await ensureYearLoaded(year);
    }
  }

  /// Reloads all currently loaded years. Useful after a bulk update (e.g. restore).
  Future<void> reloadLoadedYears() async {
    final yearsToReload = _loadedYears.toList();
    _expenses.clear();
    _loadedYears.clear();
    await _tracked(() async {
      for (final year in yearsToReload) {
        await ensureYearLoaded(year);
      }
    });
  }

  Iterable<Expense> _byYear(int year, String type) =>
      _expenses.where((e) => e.date.year == year && e.type == type);

  Iterable<Expense> _byMonth(int year, int month, String type) =>
      _expenses.where((e) =>
          e.date.year == year && e.date.month == month && e.type == type);

  /// Returns the total amount spent in a given year (expenses only), in
  /// base-currency minor units.
  int totalForYear(int year) => _memo(
      'ty:$year', () => _sumBase(_byYear(year, DbConstants.txExpense)));

  /// Returns the total income received in a given year, in base-currency
  /// minor units.
  int incomeForYear(int year) => _memo(
      'iy:$year', () => _sumBase(_byYear(year, DbConstants.txIncome)));

  /// Returns category totals (base-currency minor units) for a given year
  /// (expenses only). The returned map is cached and shared — treat it as
  /// read-only.
  Map<String, int> categoryTotalsForYear(int year) => _memo(
      'cty:$year', () => _categoryTotals(_byYear(year, DbConstants.txExpense)));

  /// Returns all transaction rows for a given year.
  List<Expense> expensesForYear(int year) =>
      _expenses.where((e) => e.date.year == year).toList();

  /// Inserts the expense and returns its new row id (e.g. for undo).
  Future<int> addExpense(Expense expense) async {
    final id = await DBService().insertExpense(expense);
    // If the year is already loaded, reload it to get the new expense
    // (or we could just add it to the list manually, but reloading is safer for consistency)
    if (_loadedYears.contains(expense.date.year)) {
      await _reloadYear(expense.date.year);
    }
    return id;
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

  /// Returns all transaction rows for a given month and year.
  List<Expense> expensesForMonth(int year, int month) {
    return _expenses
        .where((e) => e.date.year == year && e.date.month == month)
        .toList();
  }

  /// Returns only expense rows for a given month and year.
  List<Expense> spendingForMonth(int year, int month) =>
      _byMonth(year, month, DbConstants.txExpense).toList();

  /// Spend for the month broken down by account, in base-currency minor units.
  ///
  /// Keyed by account id, with null collecting rows that have no account.
  /// Answers "which card am I actually putting money on this month", which the
  /// balance on the Accounts screen cannot show — a balance is a position, not
  /// a period. Transfers are excluded along with income, so paying a card bill
  /// does not read as spending on the bank it came from.
  Map<int?, int> spendByAccountForMonth(int year, int month) =>
      _memo('sba:$year-$month', () {
        final totals = <int?, int>{};
        for (final e in _byMonth(year, month, DbConstants.txExpense)) {
          totals[e.accountId] = (totals[e.accountId] ?? 0) + baseAmountOf(e);
        }
        return totals;
      });

  /// Returns the total amount spent in a given month and year (expenses
  /// only), in base-currency minor units.
  int totalForMonth(int year, int month) => _memo('tm:$year-$month',
      () => _sumBase(_byMonth(year, month, DbConstants.txExpense)));

  /// Returns the total income received in a given month and year, in
  /// base-currency minor units.
  int incomeForMonth(int year, int month) => _memo('im:$year-$month',
      () => _sumBase(_byMonth(year, month, DbConstants.txIncome)));

  /// Returns a map of category to total (base-currency minor units) for a
  /// given month and year (expenses only). The returned map is cached and
  /// shared — treat it as read-only.
  Map<String, int> categoryTotalsForMonth(int year, int month) => _memo(
      'ctm:$year-$month',
      () => _categoryTotals(_byMonth(year, month, DbConstants.txExpense)));
}
