/// Single source of truth for INR formatting so every screen renders
/// amounts the same way (matches the existing '₹' + toStringAsFixed(2)).
String formatInr(double amount, {int decimals = 2}) =>
    '₹${amount.toStringAsFixed(decimals)}';
