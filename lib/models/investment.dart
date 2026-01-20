import '../utils/db_constants.dart';

class Investment {
  final int? id;
  final String name;
  final double amount;
  final DateTime date;
  final String type;

  Investment({
    this.id,
    required this.name,
    required this.amount,
    required this.date,
    required this.type,
  });

  Map<String, dynamic> toMap() => {
        DbConstants.colId: id,
        DbConstants.colName: name,
        DbConstants.colAmount: amount,
        DbConstants.colDate: date.toIso8601String(),
        DbConstants.colType: type,
      };

  factory Investment.fromMap(Map<String, dynamic> map) => Investment(
        id: map[DbConstants.colId],
        name: map[DbConstants.colName],
        amount: (map[DbConstants.colAmount] as num).toDouble(),
        date: DateTime.parse(map[DbConstants.colDate]),
        type: map[DbConstants.colType],
      );
}
