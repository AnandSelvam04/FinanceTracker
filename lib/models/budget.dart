import '../utils/db_constants.dart';

class Budget {
  int? id;
  String category;
  double amount;
  int year;
  int month;

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
      amount: map[DbConstants.colAmount],
      year: map[DbConstants.colYear],
      month: map[DbConstants.colMonth],
    );
  }
}
