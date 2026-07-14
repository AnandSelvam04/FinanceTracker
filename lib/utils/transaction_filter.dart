import '../models/expense.dart';

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
  final double? minAmount;
  final double? maxAmount;
  final DateTime? startDate;
  final DateTime? endDate;

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
  });

  bool matches(Expense e) {
    final q = searchQuery.toLowerCase();
    final matchesSearch = q.isEmpty ||
        e.description.toLowerCase().contains(q) ||
        e.category.toLowerCase().contains(q);

    final bool matchesPeriod;
    if (startDate != null && endDate != null) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      matchesPeriod = !d.isBefore(startDate!) && !d.isAfter(endDate!);
    } else {
      matchesPeriod =
          e.date.year == year && (month == null || e.date.month == month);
    }

    final matchesType = type == null || e.type == type;
    final matchesCategory = category == null || e.category == category;
    final matchesAccount = accountId == null || e.accountId == accountId;
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
}
