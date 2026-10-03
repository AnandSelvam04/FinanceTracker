import '../models/expense.dart';
import '../models/investment.dart';

/// Pure, testable transaction filter used by the Transactions list and its
/// "download filtered" export. A custom [startDate]/[endDate] range, when
/// set, overrides the [year]/[month] selection.
class TransactionFilter {
  final String searchQuery;
  final int year;
  final int? month;
  final String? type;
  final String? category;
  final int? accountId;
  final int? minAmount; // minor units
  final int? maxAmount; // minor units
  final DateTime? startDate;
  final DateTime? endDate;

  /// Account names by id, so a search for "HDFC" finds that account's rows.
  final Map<int, String> accountNames;

  const TransactionFilter({
    this.searchQuery = '',
    required this.year,
    this.month,
    this.type,
    this.category,
    this.accountId,
    this.minAmount,
    this.maxAmount,
    this.startDate,
    this.endDate,
    this.accountNames = const {},
  });

  /// Whether the search box matches any of [fields], or [amount] when the
  /// query is a number: "450" finds ₹450.00 (and ₹4,500.00 — it matches from
  /// the start), "1,200" finds ₹1,200.00.
  bool _searchHits(Iterable<String?> fields, int amount) {
    final q = searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    for (final f in fields) {
      if (f != null && f.toLowerCase().contains(q)) return true;
    }
    final number = q
        .replaceAll(RegExp(r'[,\s]'), '')
        .replaceFirst(RegExp(r'^[^0-9.]+'), ''); // a typed currency symbol
    if (number.isEmpty || !RegExp(r'^\d*\.?\d*$').hasMatch(number)) {
      return false;
    }
    return (amount.abs() / 100).toStringAsFixed(2).startsWith(number);
  }

  bool _inPeriod(DateTime date) {
    if (startDate != null && endDate != null) {
      final d = DateTime(date.year, date.month, date.day);
      return !d.isBefore(startDate!) && !d.isAfter(endDate!);
    }
    return date.year == year && (month == null || date.month == month);
  }

  bool matches(Expense e) {
    final matchesSearch = _searchHits([
      e.description,
      e.category,
      e.paymentMode,
      e.note,
      accountNames[e.accountId],
      accountNames[e.toAccountId],
    ], e.amount);

    final matchesPeriod = _inPeriod(e.date);

    final matchesType = type == null || e.type == type;
    final matchesCategory = category == null || e.category == category;
    // Either leg: a transfer stores the source in accountId and the
    // destination in toAccountId, so matching only the source hid incoming
    // transfers — a credit card's bill payments never showed up under the
    // card, and the filtered list would not reconcile to the balance the
    // Accounts screen computes (which does count both legs).
    final matchesAccount = accountId == null ||
        e.accountId == accountId ||
        e.toAccountId == accountId;
    final matchesMin = minAmount == null || e.amount >= minAmount!;
    final matchesMax = maxAmount == null || e.amount <= maxAmount!;

    return matchesSearch &&
        matchesPeriod &&
        matchesType &&
        matchesCategory &&
        matchesAccount &&
        matchesMin &&
        matchesMax;
  }

  List<Expense> apply(List<Expense> all) => all.where(matches).toList();

  /// Investments paid from (or back into) the filtered account. They move
  /// its balance, so the account's list has to show them to add up. Only
  /// with an account chosen and no type or category filter, which an
  /// investment has no value for.
  List<Investment> investmentsFor(List<Investment> all) {
    if (accountId == null || type != null || category != null) return [];
    return [
      for (final i in all)
        if (i.accountId == accountId &&
            _inPeriod(i.date) &&
            (minAmount == null || i.amount.abs() >= minAmount!) &&
            (maxAmount == null || i.amount.abs() <= maxAmount!) &&
            _searchHits([i.name, i.type, 'investment'], i.amount))
          i,
    ];
  }
}
