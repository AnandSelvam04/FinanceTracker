import '../utils/db_constants.dart';

/// A transaction row: an expense (default), an income, or a transfer
/// between accounts (accountId = source, toAccountId = destination).
class Expense {
  final int? id;
  final String description;
  final double amount;
  final DateTime date;
  final String category;
  final String paymentMode;
  final String type;
  final int? accountId;
  final int? toAccountId;

  Expense({
    this.id,
    required this.description,
    required this.amount,
    required this.date,
    required this.category,
    required this.paymentMode,
    this.type = DbConstants.txExpense,
    this.accountId,
    this.toAccountId,
  });

  bool get isExpense => type == DbConstants.txExpense;
  bool get isIncome => type == DbConstants.txIncome;
  bool get isTransfer => type == DbConstants.txTransfer;

  Map<String, dynamic> toMap() => {
        DbConstants.colId: id,
        DbConstants.colDescription: description,
        DbConstants.colAmount: amount,
        DbConstants.colDate: date.toIso8601String(),
        DbConstants.colCategory: category,
        DbConstants.colPaymentMode: paymentMode,
        DbConstants.colType: type,
        DbConstants.colAccountId: accountId,
        DbConstants.colToAccountId: toAccountId,
      };

  factory Expense.fromMap(Map<String, dynamic> map) => Expense(
        id: map[DbConstants.colId],
        description: map[DbConstants.colDescription],
        amount: (map[DbConstants.colAmount] as num).toDouble(),
        date: DateTime.parse(map[DbConstants.colDate]),
        category: map[DbConstants.colCategory],
        paymentMode: map[DbConstants.colPaymentMode],
        // Rows from schema v3 databases or old backups have no type column.
        type: map[DbConstants.colType] ?? DbConstants.txExpense,
        accountId: map[DbConstants.colAccountId],
        toAccountId: map[DbConstants.colToAccountId],
      );
}
