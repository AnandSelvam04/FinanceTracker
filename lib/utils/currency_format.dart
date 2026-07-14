/// Configurable currency symbol, set once from SettingsProvider on startup
/// so every screen formats amounts consistently.
class CurrencyFormat {
  CurrencyFormat._();
  static String symbol = '₹';
}

/// Formats a money amount with the app's configured currency symbol.
String formatMoney(double amount, {int decimals = 2}) =>
    '${CurrencyFormat.symbol}${amount.toStringAsFixed(decimals)}';
