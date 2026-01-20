import '../utils/db_constants.dart';

class Expense {
  final int? id;
  final String description;
  final double amount;
  final DateTime date;
  final String category;
  final String paymentMode;

  Expense({
    this.id,
    required this.description,
    required this.amount,
    required this.date,
    required this.category,
    required this.paymentMode,
  });

  Map<String, dynamic> toMap() => {
        DbConstants.colId: id,
        DbConstants.colDescription: description,
        DbConstants.colAmount: amount,
        DbConstants.colDate: date.toIso8601String(),
        DbConstants.colCategory: category,
        DbConstants.colPaymentMode: paymentMode,
      };

  factory Expense.fromMap(Map<String, dynamic> map) => Expense(
        id: map[DbConstants.colId],
        description: map[DbConstants.colDescription],
        amount: (map[DbConstants.colAmount] as num).toDouble(),
        date: DateTime.parse(map[DbConstants.colDate]),
        category: map[DbConstants.colCategory],
        paymentMode: map[DbConstants.colPaymentMode],
      );
}
