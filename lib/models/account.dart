import '../utils/db_constants.dart';

class Account {
  final int? id;
  final String name;
  final String type; // cash | bank | upi | credit_card

  /// Opening balance in minor units (paise/cents).
  final int openingBalance;
  final int? color;

  Account({
    this.id,
    required this.name,
    required this.type,
    this.openingBalance = 0,
    this.color,
  });

  static const types = ['cash', 'bank', 'upi', 'credit_card'];

  static String typeLabel(String type) {
    switch (type) {
      case 'cash':
        return 'Cash';
      case 'bank':
        return 'Bank';
      case 'upi':
        return 'UPI';
      case 'credit_card':
        return 'Credit Card';
      default:
        return type;
    }
  }

  Map<String, dynamic> toMap() => {
        DbConstants.colId: id,
        DbConstants.colName: name,
        DbConstants.colType: type,
        DbConstants.colOpeningBalance: openingBalance,
        DbConstants.colColor: color,
      };

  factory Account.fromMap(Map<String, dynamic> map) => Account(
        id: map[DbConstants.colId],
        name: map[DbConstants.colName],
        type: map[DbConstants.colType] ?? 'cash',
        openingBalance:
            ((map[DbConstants.colOpeningBalance] ?? 0) as num).round(),
        color: map[DbConstants.colColor],
      );
}
