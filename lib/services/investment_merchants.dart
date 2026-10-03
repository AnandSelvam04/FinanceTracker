/// Recognises a bank debit that is money being invested — a SIP, a broker
/// top-up, an NPS contribution — and guesses which investment type it is.
///
/// Without this every such alert arrived on the SMS review screen as an
/// expense, and the switch to Investment (plus picking the type) had to be
/// made by hand on each one, every month.
///
/// Pure Dart, and like `MerchantCategories` deliberately limited to names
/// that are unambiguous: a missed guess costs one tap, but a false one would
/// take spending out of the budgets.
class InvestmentMerchants {
  InvestmentMerchants._();

  /// Checked in order, so a specific name ("coin by zerodha", a mutual-fund
  /// platform) wins over the broker it belongs to. Types are
  /// `Investment.builtInTypes` names.
  static final List<(RegExp, String)> _patterns = [
    for (final (words, type) in const [
      (
        [
          r'\bsip\b', r'mutual\s*fund', r'\bmfs?\b', //
          r'coin\s*by\s*zerodha', r'\bkuvera\b', r'\bkfin', r'\bcams\b',
          r'bse\s*star', r'\bmf\s*utilit', r'\bgroww\b', r'\bet\s*money\b',
          r'\bpaytm\s*money\b', r'\bbse\s*(ltd|limited)\b',
        ],
        'Mutual Funds'
      ),
      (
        [
          r'\bnps\b', r'nsdl\s*e-?gov', r'\bprotean\b', //
          r'national\s*pension',
        ],
        'NPS'
      ),
      (
        [
          r'\bsafegold\b', r'\baugmont\b', r'\bmmtc\b', r'digital\s*gold', //
          r'\bsgb\b', r'sovereign\s*gold',
        ],
        'Gold'
      ),
      ([r'fixed\s*deposit', r'\bfd\s*(booking|opened|created)\b'], 'FD'),
      (
        [
          r'\bzerodha\b', r'\bupstox\b', r'\bangel\s*(one|broking)\b', //
          r'\b5\s*paisa\b', r'\biccl\b', r'indian\s*clearing',
          r'\bnsccl\b', r'nse\s*clearing', r'\bsmallcase\b',
          r'(icici|hdfc|kotak|sbi|axis)\s*securities', r'\bmotilal\b',
        ],
        'Stocks'
      ),
    ])
      for (final w in words) (RegExp(w), type),
  ];

  /// The investment type the merchant name [text] points to, or null when
  /// nothing marks it as an investment.
  static String? guessType(String text) {
    final t = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (t.trim().isEmpty) return null;
    for (final (pattern, type) in _patterns) {
      if (pattern.hasMatch(t)) return type;
    }
    return null;
  }
}
