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

  /// Credit-card billing cycle. [statementDay] is the day of the month the
  /// statement is generated (the cycle closes), [dueDay] the day payment is
  /// due. Both null unless the user set a cycle on a credit-card account; used
  /// to compute the amount owed and remind before the due date.
  final int? statementDay;
  final int? dueDay;

  Account({
    this.id,
    required this.name,
    required this.type,
    this.openingBalance = 0,
    this.color,
    this.currency,
    this.rate = 1.0,
    this.last4,
    this.statementDay,
    this.dueDay,
  });

  /// Whether this credit card has a billing cycle configured.
  bool get hasBillingCycle =>
      type == 'credit_card' && statementDay != null && dueDay != null;

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
        DbConstants.colStatementDay: statementDay,
        DbConstants.colDueDay: dueDay,
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
        // Rows/backups from before schema v13 have no billing-cycle columns.
        statementDay: (map[DbConstants.colStatementDay] as num?)?.toInt(),
        dueDay: (map[DbConstants.colDueDay] as num?)?.toInt(),
      );
}
