/// Money is stored and computed as integer minor units (e.g. paise/cents)
/// to avoid floating-point rounding errors. Convert to/from the double the
/// user types only at the UI edges via these helpers.
class CurrencyFormat {
  CurrencyFormat._();
  static String symbol = '₹';
}

/// Converts a user-entered major-unit amount (e.g. 12.50 rupees) to minor
/// units (1250 paise).
int rupeesToMinor(double major) => (major * 100).round();

/// Converts minor units back to a major-unit double for display/parsing.
double minorToMajor(int minor) => minor / 100;

/// Parses a user-entered amount string into minor units, or null if invalid.
int? parseMinor(String input) {
  final major = double.tryParse(input.trim());
  return major == null ? null : rupeesToMinor(major);
}

/// Formats minor units with the configured currency symbol and 2 decimals.
String formatMoney(int minor) =>
    '${CurrencyFormat.symbol}${(minor / 100).toStringAsFixed(2)}';

/// Like [formatMoney] but with an explicit [symbol], for accounts held in a
/// currency other than the app's base currency.
String formatMoneyIn(String symbol, int minor) =>
    '$symbol${(minor / 100).toStringAsFixed(2)}';

/// Formats minor units rounded to whole major units (no decimals).
String formatMoneyRounded(int minor) =>
    '${CurrencyFormat.symbol}${(minor / 100).round()}';

/// Converts an [amount] in an account currency (minor units) to base-currency
/// minor units using [rate] (base units per 1 account-currency unit).
int toBaseMinor(int amount, double rate) => (amount * rate).round();

/// A major-unit string (e.g. "12.50") for pre-filling edit fields.
String minorToEditString(int minor) => (minor / 100).toStringAsFixed(2);
