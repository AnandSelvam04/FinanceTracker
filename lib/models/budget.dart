import '../utils/db_constants.dart';

class Budget {
  /// Sentinel [category] for the single overall monthly budget — a cap on all
  /// spending for a month, not tied to one category. Stored in the same table
  /// as category budgets; the double-underscore keeps it from colliding with a
  /// real category name.
  static const String overallCategory = '__overall__';

  /// Label shown for the overall budget in the UI.
  static const String overallLabel = 'Total (all categories)';

  int? id;
  String category;

  /// Amount in minor units (paise/cents).
  int amount;
  int year;
  int month;

  /// Whether this is the overall monthly cap rather than a per-category one.
  bool get isOverall => category == overallCategory;

  Budget({
    this.id,
    required this.category,
    required this.amount,
    required this.year,
    required this.month,
  });

  Map<String, dynamic> toMap() {
    return {
      DbConstants.colId: id,
      DbConstants.colCategory: category,
      DbConstants.colAmount: amount,
      DbConstants.colYear: year,
      DbConstants.colMonth: month,
    };
  }

  factory Budget.fromMap(Map<String, dynamic> map) {
    return Budget(
      id: map[DbConstants.colId],
      category: map[DbConstants.colCategory],
      amount: (map[DbConstants.colAmount] as num).round(),
      year: map[DbConstants.colYear],
      month: map[DbConstants.colMonth],
    );
  }
}
