import '../utils/db_constants.dart';

class Investment {
  /// The built-in investment types offered in the Type dropdown. 'Other' is
  /// always last and lets the user type a custom type in a text box, so this
  /// list doesn't need to grow every time someone tracks a new instrument.
  static const List<String> builtInTypes = [
    'Stocks',
    'Mutual Funds',
    'Bonds',
    'FD',
    'NPS',
    'Gold',
    'Silver',
    'Other',
  ];

  /// Sentinel value for the dropdown entry that reveals the custom-type field.
  static const String otherType = 'Other';

  /// The type a new contribution starts on when none is chosen.
  static const String defaultType = 'Stocks';

  final int? id;
  final String name;

  /// Amount in minor units (paise/cents). Positive for a contribution, negative
  /// for a withdrawal — so a type's running total falls when money is taken
  /// back out.
  final int amount;
  final DateTime date;
  final String type;

  /// The account the money came from, or null when it isn't tracked. A bank
  /// or debit account's balance drops by [amount]; on a credit card it is
  /// added to what's owed and to the card's statement.
  final int? accountId;

  /// A negative amount records money pulled back out of the holding rather than
  /// put in.
  bool get isWithdrawal => amount < 0;

  Investment({
    this.id,
    required this.name,
    required this.amount,
    required this.date,
    required this.type,
    this.accountId,
  });

  Map<String, dynamic> toMap() => {
        DbConstants.colId: id,
        DbConstants.colName: name,
        DbConstants.colAmount: amount,
        DbConstants.colDate: date.toIso8601String(),
        DbConstants.colType: type,
        DbConstants.colAccountId: accountId,
      };

  factory Investment.fromMap(Map<String, dynamic> map) => Investment(
        id: map[DbConstants.colId],
        name: map[DbConstants.colName],
        amount: (map[DbConstants.colAmount] as num).round(),
        date: DateTime.parse(map[DbConstants.colDate]),
        type: map[DbConstants.colType],
        accountId: (map[DbConstants.colAccountId] as num?)?.toInt(),
      );
}

/// What an investment type's holdings are worth now, as last entered by the
/// user. Shown next to what was put in; the ledger and net worth stay at
/// cost, since the app has no market prices of its own.
class InvestmentValue {
  /// Minor units.
  final int amount;

  /// When the value was entered.
  final DateTime asOf;

  const InvestmentValue({required this.amount, required this.asOf});
}
