/// A first guess at the category for a merchant seen for the first time.
///
/// [CategoryMemory] only knows merchants you have filed before, so every new
/// one used to arrive as "Other". Well-known Indian merchants and billers are
/// common enough to recognise by name, which turns the first import of each
/// into a glance rather than a pick. The categories are the Add Expense
/// screen's built-in ones, so a guess lines up with budgets on those names.
///
/// Pure Dart, and deliberately a short list of unambiguous names: a wrong
/// guess costs a tap to fix, but a vague keyword ("pay", "store") would be
/// wrong more often than right.
class MerchantCategories {
  MerchantCategories._();

  static const Map<String, List<String>> _keywords = {
    'Food': [
      'swiggy', 'zomato', 'dominos', 'domino', 'mcdonald', 'mcdonalds', //
      'kfc', 'pizza hut', 'pizzahut', 'burger king', 'starbucks', 'subway',
      'haldiram', 'chaayos', 'cafe coffee day', 'ccd', 'eatsure', 'faasos',
      'bigbasket', 'blinkit', 'grofers', 'zepto', 'instamart', 'dmart',
      'jiomart', 'more retail', 'spencers', 'nature basket', 'milkbasket',
      'country delight', 'licious', 'freshtohome', 'restaurant', 'bakery',
      'dhaba', 'sweets',
    ],
    'Transport': [
      'uber', 'ola', 'olacabs', 'rapido', 'blusmart', 'namma yatri', //
      'metro', 'fastag', 'irctc', 'redbus', 'indian oil', 'indianoil', 'iocl',
      'hpcl', 'bpcl', 'bharat petroleum', 'hindustan petroleum', 'shell',
      'petrol', 'fuel', 'parking', 'makemytrip', 'goibibo', 'indigo',
      'air india', 'akasa', 'spicejet', 'cleartrip', 'ixigo', 'yatra',
    ],
    'Shopping': [
      'amazon', 'flipkart', 'myntra', 'ajio', 'nykaa', 'meesho', 'tata cliq', //
      'tatacliq', 'croma', 'reliance digital', 'vijay sales', 'decathlon',
      'ikea', 'lifestyle', 'westside', 'pantaloons', 'max fashion', 'zudio',
      'trends', 'firstcry', 'lenskart', 'snapdeal', 'shoppers stop',
    ],
    'Bills': [
      'airtel', 'jio', 'vodafone', 'vodafone idea', 'bsnl', 'act fibernet', //
      'hathway', 'tata play', 'tataplay', 'dish tv', 'sun direct',
      'electricity', 'bescom', 'tneb', 'tangedco', 'msedcl', 'mahadiscom',
      'bses', 'tata power', 'adani electricity', 'torrent power', 'kseb',
      'water board', 'indane', 'bharat gas', 'hp gas', 'mahanagar gas',
      'igl', 'broadband', 'lic', 'insurance', 'policybazaar',
    ],
    'Entertainment': [
      'netflix', 'spotify', 'hotstar', 'disney', 'prime video', 'sonyliv', //
      'zee5', 'jiocinema', 'youtube', 'bookmyshow', 'pvr', 'inox', 'cinepolis',
      'apple media', 'google play', 'steam', 'playstation', 'gaana',
      'wynk', 'audible',
    ],
    'Health': [
      'apollo', 'pharmeasy', '1mg', 'tata 1mg', 'netmeds', 'medplus', //
      'practo', 'hospital', 'clinic', 'pharmacy', 'medical', 'chemist',
      'diagnostic', 'diagnostics', 'cult.fit', 'cultfit', 'healthkart',
    ],
    'Education': [
      'udemy', 'coursera', 'byju', 'byjus', 'unacademy', 'vedantu', //
      'upgrad', 'simplilearn', 'school', 'college', 'university', 'tuition',
      'physics wallah',
    ],
  };

  /// Keyword patterns, compiled once. Each keyword must stand as a whole word
  /// (or the name part of a UPI handle — "swiggy@icici", "zomato-order@...")
  /// so "ola" doesn't match "cola" and "lab" doesn't match "label".
  static final List<(RegExp, String)> _patterns = [
    for (final entry in _keywords.entries)
      for (final keyword in entry.value)
        (
          RegExp('(^|[^a-z0-9])${RegExp.escape(keyword)}(\$|[^a-z0-9])'),
          entry.key,
        ),
  ];

  /// The category a merchant named [description] most likely belongs to, or
  /// null when the name isn't one this list knows.
  static String? guess(String description) {
    final name = description.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (name.trim().isEmpty) return null;
    for (final (pattern, category) in _patterns) {
      if (pattern.hasMatch(name)) return category;
    }
    return null;
  }
}
