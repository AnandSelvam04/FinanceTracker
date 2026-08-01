import '../utils/currency_format.dart';
import '../utils/db_constants.dart';

class Account {
  final int? id;
  final String name;
  final String type; // cash | bank | upi | credit_card

  /// Opening balance in minor units (paise/cents), in this account's currency.
  final int openingBalance;
  final int? color;

  /// Currency symbol this account is held in; null means the app base currency.
  final String? currency;

  /// Exchange rate to the base currency (base units per 1 account-currency
  /// unit). 1.0 when the account is already in the base currency.
  final double rate;

  /// Last four digits of the account or card number, as they appear in bank
  /// SMS alerts ("A/c XX4821", "Card ending 5678"). Null when the user has not
  /// set one, which simply means SMS import cannot auto-route to this account.
  final String? last4;

  Account({
    this.id,
    required this.name,
    required this.type,
    this.openingBalance = 0,
    this.color,
    this.currency,
    this.rate = 1.0,
    this.last4,
  });

  /// The symbol to display this account's amounts in.
  String get symbol => currency ?? CurrencyFormat.symbol;

  /// Whether this account is held in a non-base currency.
  bool get isForeign => currency != null && currency != CurrencyFormat.symbol;

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
        DbConstants.colCurrency: currency,
        DbConstants.colRate: rate,
        DbConstants.colLast4: last4,
      };

  factory Account.fromMap(Map<String, dynamic> map) => Account(
        id: map[DbConstants.colId],
        name: map[DbConstants.colName],
        type: map[DbConstants.colType] ?? 'cash',
        openingBalance:
            ((map[DbConstants.colOpeningBalance] ?? 0) as num).round(),
        color: map[DbConstants.colColor],
        currency: map[DbConstants.colCurrency] as String?,
        rate: ((map[DbConstants.colRate] ?? 1.0) as num).toDouble(),
        // Rows/backups from before schema v10 have no last4 column.
        last4: map[DbConstants.colLast4] as String?,
      );
}
