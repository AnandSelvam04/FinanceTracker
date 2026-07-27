/// Money is stored and computed as integer minor units (e.g. paise/cents)
/// to avoid floating-point rounding errors. Convert to/from the double the
/// user types only at the UI edges via these helpers.
class CurrencyFormat {
  CurrencyFormat._();
  static String symbol = '₹';
}

/// Largest amount the app accepts, in major units (one trillion).
///
/// Minor units are stored in a 64-bit int, and `.round()` on a double beyond
/// that range throws an unhandled `UnsupportedError` — so pasting `1e300` into
/// an amount field used to crash rather than fail validation. This ceiling is
/// far above any realistic personal-finance figure while leaving plenty of
/// headroom for sums.
const double maxMajorAmount = 1e12;

/// Whether [major] is a finite amount within [maxMajorAmount].
bool isAmountInRange(double major) =>
    major.isFinite && major.abs() <= maxMajorAmount;

/// Converts a user-entered major-unit amount (e.g. 12.50 rupees) to minor
/// units (1250 paise).
///
/// Callers must screen the input with [isAmountInRange] first — [parseMinor]
/// and the CSV importer already do.
int rupeesToMinor(double major) => (major * 100).round();

/// Converts minor units back to a major-unit double for display/parsing.
double minorToMajor(int minor) => minor / 100;

/// Parses a user-entered amount string into minor units, or null if it isn't a
/// number or is out of range.
int? parseMinor(String input) {
  final major = double.tryParse(input.trim());
  if (major == null || !isAmountInRange(major)) return null;
  return rupeesToMinor(major);
}

/// Formats minor units with the configured currency symbol and 2 decimals.
String formatMoney(int minor) =>
    '${CurrencyFormat.symbol}${(minor / 100).toStringAsFixed(2)}';

/// Formats a possibly-negative amount with the minus sign *before* the
/// currency symbol — "-₹75.00", the conventional presentation.
///
/// [formatMoney] puts the symbol first, so a negative value comes out as
/// "₹-75.00". Use this wherever the amount can legitimately be negative
/// (net totals, net worth, balances).
String formatMoneySigned(int minor) =>
    '${minor < 0 ? '-' : ''}${formatMoney(minor.abs())}';

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

/// Shared `TextFormField.validator` for a money amount: returns null when the
/// text is a usable amount, or the message to display.
///
/// Centralised so every amount field rejects the same things — notably values
/// past [maxMajorAmount], which used to crash on save rather than fail
/// validation. Pass [allowZero] for caps and budgets that may legitimately be
/// zero.
String? validateAmountField(String? value, {bool allowZero = false}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Enter an amount';
  final major = double.tryParse(text);
  if (major == null) return 'Enter a valid amount';
  if (!isAmountInRange(major)) return 'That amount is too large';
  if (major < 0) return 'Enter a positive amount';
  if (!allowZero && major == 0) return 'Enter an amount greater than zero';
  return null;
}
