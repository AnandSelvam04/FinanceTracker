/// Turns the raw text ML Kit reads off a bill/receipt photo into a draft
/// transaction (amount, date, merchant).
///
/// Pure Dart on purpose: no plugin, no Flutter. The camera/OCR plumbing lives
/// behind [ReceiptScanner] and hands the recognized text to this file, so all
/// of the logic that can actually be wrong is unit-testable without a device.
///
/// Everything here is best-effort pattern matching against receipt layouts
/// that vary wildly, so nothing it produces is saved automatically — the
/// results only pre-fill the Add Expense form for the user to confirm.
class ReceiptParser {
  ReceiptParser._();

  /// Wording next to the figure a shopper actually pays.
  static final _totalWords = RegExp(
      r'\b(grand\s*total|total\s*(?:amount|due|payable)?|amount\s*(?:due|payable)|balance\s*due|net\s*(?:amount|payable)?|to\s*pay|payable)\b',
      caseSensitive: false);

  /// "Subtotal" contains "total"; a subtotal is never the figure we want.
  static final _subtotalWords =
      RegExp(r'\bsub[\s-]*total\b', caseSensitive: false);

  /// Lines whose amount is a component or a settlement detail, not the bill
  /// total — used to keep the fallback "largest number" guess honest.
  static final _noiseWords = RegExp(
      r'\b(sub[\s-]*total|tax|gst|vat|cgst|sgst|igst|cess|discount|change|tender(?:ed)?|cash|card|round(?:ing|\s*off)?|qty|item|phone|tel|invoice\s*no|bill\s*no|order\s*no)\b',
      caseSensitive: false);

  /// A money figure, optionally prefixed by a currency marker:
  /// "₹1,234.50", "Rs. 499", "$ 12.00", "1234.50".
  static final _money = RegExp(
      r'(?:₹|rs\.?|inr|\$|usd|€|£)?\s*(\d{1,3}(?:[.,]\d{3})*(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)',
      caseSensitive: false);

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Parses [rawText] (ML Kit's line-broken output) into a [ParsedReceipt].
  static ParsedReceipt parse(String rawText) {
    final lines = rawText
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return ParsedReceipt(
      amountMinor: _findAmount(lines),
      date: _findDate(rawText),
      merchant: _findMerchant(lines),
      rawText: rawText,
    );
  }

  // --- Amount ---------------------------------------------------------------

  static int? _findAmount(List<String> lines) {
    final totals = <int>[];
    final plausible = <int>[]; // money not on a "noise" line
    final all = <int>[];

    for (final line in lines) {
      final lower = line.toLowerCase();
      final isTotal =
          _totalWords.hasMatch(lower) && !_subtotalWords.hasMatch(lower);
      final isNoise = _noiseWords.hasMatch(lower);
      for (final m in _money.allMatches(line)) {
        final minor = parseAmountToken(m.group(1)!);
        if (minor == null || minor <= 0) continue;
        all.add(minor);
        if (isTotal) totals.add(minor);
        if (!isNoise) plausible.add(minor);
      }
    }

    // A labelled total wins; the grand total is the largest of them (it is
    // never smaller than a subtotal printed on the same "total" wording).
    if (totals.isNotEmpty) return totals.reduce((a, b) => a > b ? a : b);
    // Otherwise the bill total is almost always the largest ordinary figure.
    if (plausible.isNotEmpty) return plausible.reduce((a, b) => a > b ? a : b);
    if (all.isNotEmpty) return all.reduce((a, b) => a > b ? a : b);
    return null;
  }

  /// Parses a single money token ("1,234.50", "1.234,50", "499") into minor
  /// units. Handles both `.` and `,` as either thousands or decimal separator,
  /// deciding by the length of the final group. Exposed for unit tests.
  static int? parseAmountToken(String token) {
    var s = token.trim().replaceAll(RegExp(r'[^0-9.,]'), '');
    if (s.isEmpty) return null;

    final lastDot = s.lastIndexOf('.');
    final lastComma = s.lastIndexOf(',');
    final lastSep = lastDot > lastComma ? lastDot : lastComma;

    int rupees;
    int paise = 0;
    if (lastSep >= 0) {
      final frac = s.substring(lastSep + 1);
      // A final group of 1–2 digits reads as the decimal part; a 3-digit group
      // (or none) means the separator was a thousands grouping.
      if (frac.length == 1 || frac.length == 2) {
        final intPart = s.substring(0, lastSep).replaceAll(RegExp(r'[.,]'), '');
        rupees = int.tryParse(intPart.isEmpty ? '0' : intPart) ?? 0;
        final f = int.tryParse(frac) ?? 0;
        paise = frac.length == 1 ? f * 10 : f;
      } else {
        rupees = int.tryParse(s.replaceAll(RegExp(r'[.,]'), '')) ?? 0;
      }
    } else {
      rupees = int.tryParse(s) ?? 0;
    }
    return rupees * 100 + paise;
  }

  // --- Date -----------------------------------------------------------------

  static DateTime? _findDate(String text) {
    // ISO first: unambiguous.
    final iso = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b').firstMatch(text);
    if (iso != null) {
      final d = _build(int.parse(iso.group(1)!), int.parse(iso.group(2)!),
          int.parse(iso.group(3)!));
      if (d != null) return d;
    }

    // Numeric d/m/y (day-first, the common case outside the US); fall back to
    // month-first only when the first field cannot be a day.
    final dmy =
        RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b').firstMatch(text);
    if (dmy != null) {
      final a = int.parse(dmy.group(1)!);
      final b = int.parse(dmy.group(2)!);
      final y = _year(dmy.group(3)!);
      final d = _build(y, b, a) ?? _build(y, a, b);
      if (d != null) return d;
    }

    // "12 Aug 2025" / "12-Aug-25".
    final dMonY = RegExp(
            r'\b(\d{1,2})[\s\-]*([A-Za-z]{3,})[\s\-,]*(\d{2,4})\b')
        .firstMatch(text);
    if (dMonY != null) {
      final mon = _months[dMonY.group(2)!.toLowerCase().substring(0, 3)];
      if (mon != null) {
        final d = _build(_year(dMonY.group(3)!), mon, int.parse(dMonY.group(1)!));
        if (d != null) return d;
      }
    }

    // "Aug 12, 2025".
    final monDY = RegExp(
            r'\b([A-Za-z]{3,})[\s\-]*(\d{1,2})[\s\-,]*(\d{2,4})\b')
        .firstMatch(text);
    if (monDY != null) {
      final mon = _months[monDY.group(1)!.toLowerCase().substring(0, 3)];
      if (mon != null) {
        final d = _build(_year(monDY.group(3)!), mon, int.parse(monDY.group(2)!));
        if (d != null) return d;
      }
    }
    return null;
  }

  static int _year(String raw) {
    final y = int.parse(raw);
    return raw.length <= 2 ? 2000 + y : y;
  }

  static DateTime? _build(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31 || y < 2000 || y > 2100) {
      return null;
    }
    final dt = DateTime(y, m, d);
    // Reject overflow (e.g. day 31 of a 30-day month rolling into next month).
    if (dt.month != m || dt.day != d) return null;
    return dt;
  }

  // --- Merchant -------------------------------------------------------------

  static final _dateLike =
      RegExp(r'\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}|\b\d{4}-\d{2}-\d{2}\b');

  static String? _findMerchant(List<String> lines) {
    for (final line in lines) {
      final letters = line.replaceAll(RegExp(r'[^A-Za-z]'), '');
      // Skip lines that are mostly digits/symbols, dates, or too short to be a
      // store name.
      if (letters.length < 3) continue;
      if (_dateLike.hasMatch(line)) continue;
      if (RegExp(r'^\+?\d[\d\s\-]{6,}$').hasMatch(line)) continue; // phone
      if (letters.length < line.replaceAll(' ', '').length * 0.4) continue;
      final cleaned = line.replaceAll(RegExp(r'\s+'), ' ').trim();
      return cleaned.length > 40 ? cleaned.substring(0, 40).trim() : cleaned;
    }
    return null;
  }
}

/// A best-effort draft read off a receipt photo. Any field may be null when the
/// OCR text didn't yield a confident guess.
class ParsedReceipt {
  final int? amountMinor;
  final DateTime? date;
  final String? merchant;
  final String rawText;

  const ParsedReceipt({
    this.amountMinor,
    this.date,
    this.merchant,
    required this.rawText,
  });

  bool get isEmpty => amountMinor == null && date == null && merchant == null;
}
