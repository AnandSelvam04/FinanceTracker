import '../utils/db_constants.dart';

/// A saved one-tap quick-add template for a common transaction.
class TxTemplate {
  final int? id;
  final String name;
  final String description;
  final double amount;
  final String category;
  final String type; // expense | income
  final int? accountId;

  TxTemplate({
    this.id,
    required this.name,
    required this.description,
    required this.amount,
    required this.category,
    this.type = DbConstants.txExpense,
    this.accountId,
  });

  Map<String, dynamic> toMap() => {
        DbConstants.colId: id,
        DbConstants.colName: name,
        DbConstants.colDescription: description,
        DbConstants.colAmount: amount,
        DbConstants.colCategory: category,
        DbConstants.colType: type,
        DbConstants.colAccountId: accountId,
      };

  factory TxTemplate.fromMap(Map<String, dynamic> map) => TxTemplate(
        id: map[DbConstants.colId],
        name: map[DbConstants.colName] ?? '',
        description: map[DbConstants.colDescription] ?? '',
        amount: ((map[DbConstants.colAmount] ?? 0) as num).toDouble(),
        category: map[DbConstants.colCategory] ?? 'Other',
        type: map[DbConstants.colType] ?? DbConstants.txExpense,
        accountId: map[DbConstants.colAccountId],
      );
}
