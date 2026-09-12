import '../utils/db_constants.dart';
import 'receipt_parser.dart';

/// Turns a spoken sentence ("spent 250 on food at dominos") into a draft
/// transaction.
///
/// Pure Dart on purpose: the speech plugin lives behind [SpeechInputService]
/// and hands the recognized words to this file, so the interpretation logic is
/// unit-testable without a microphone. Results only pre-fill the Add Expense
/// form — nothing is saved without confirmation.
class VoiceExpenseParser {
  VoiceExpenseParser._();

  /// Wording that means money came in rather than went out.
  static final _incomeWords = RegExp(
      r'\b(income|received?|salary|credited?|earned?|got|deposit(?:ed)?|refund(?:ed)?|bonus)\b');

  /// First money-looking token in the sentence.
  static final _amount = RegExp(r'(\d[\d,]*(?:\.\d{1,2})?)');

  /// Command lead-ins to strip from the description ("add an expense of …").
  static final _lead = RegExp(
      r'^\s*(?:please\s+)?(?:add|record|create|new|log|enter|make)\s+(?:an?\s+)?(?:new\s+)?(?:expense|income|transaction|spending|spend|payment)\s*(?:of\s+|for\s+)?',
      caseSensitive: false);

  /// Currency/quantity words that shouldn't survive into the description.
  static final _currencyWords = RegExp(
      r'\b(rupees?|rs\.?|inr|dollars?|usd|euros?|paise|cents?|bucks?)\b',
      caseSensitive: false);

  /// Captures the category after "on"/"for" ("… for transport …").
  static final _afterFor = RegExp(
      r'\b(?:on|for|towards|category)\s+([a-z][a-z]*(?:\s+[a-z]+)?)',
      caseSensitive: false);

  /// Captures a merchant after "at"/"from" ("… at Dominos").
  static final _afterAt = RegExp(
      r'\b(?:at|from)\s+(.+)$',
      caseSensitive: false);

  static final _trailingDate =
      RegExp(r'\b(yesterday|today|tomorrow|last\s+\w+)\b.*$', caseSensitive: false);

  static ParsedVoiceExpense parse(String transcript,
      {List<String> knownCategories = const []}) {
    final text = transcript.trim();
    final lower = text.toLowerCase();

    final type =
        _incomeWords.hasMatch(lower) ? DbConstants.txIncome : DbConstants.txExpense;

    int? amount;
    final am = _amount.firstMatch(text);
    if (am != null) {
      final parsed = ReceiptParser.parseAmountToken(am.group(1)!);
      if (parsed != null && parsed > 0) amount = parsed;
    }

    var category = _matchKnown(lower, knownCategories) ?? _categoryPhrase(lower);
    final merchant = _merchant(text);

    // Prefer a named merchant, then the category, as the human-readable label.
    var description = merchant ?? (category == null ? null : _titleCase(category));
    description ??= _remainder(text);

    return ParsedVoiceExpense(
      amountMinor: amount,
      category: category == null ? null : _titleCase(category),
      description: (description == null || description.isEmpty) ? null : description,
      type: type,
    );
  }

  static String? _matchKnown(String lower, List<String> categories) {
    final sorted = [...categories]
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final c in sorted) {
      final needle = c.toLowerCase().trim();
      if (needle.isEmpty) continue;
      if (RegExp('\\b${RegExp.escape(needle)}\\b').hasMatch(lower)) return needle;
    }
    return null;
  }

  static String? _categoryPhrase(String lower) {
    final m = _afterFor.firstMatch(lower);
    if (m == null) return null;
    var phrase = m.group(1)!.trim();
    // Drop a trailing "at"/merchant that the greedy word pair may have grabbed.
    phrase = phrase.replaceAll(RegExp(r'\b(at|from|on)\b.*$'), '').trim();
    return phrase.isEmpty ? null : phrase;
  }

  static String? _merchant(String text) {
    final m = _afterAt.firstMatch(text);
    if (m == null) return null;
    var merchant = m.group(1)!.trim();
    merchant = merchant.replaceAll(_trailingDate, '').trim();
    merchant = merchant.replaceAll(RegExp(r'[.,;]+$'), '').trim();
    return merchant.isEmpty ? null : _titleCase(merchant);
  }

  static String? _remainder(String text) {
    var s = text.replaceFirst(_lead, '');
    s = s.replaceAll(_amount, ' ');
    s = s.replaceAll(_currencyWords, ' ');
    s = s.replaceAll(RegExp(r'\b(on|for|at|from|towards|category|of)\b',
        caseSensitive: false), ' ');
    s = s.replaceAll(_trailingDate, ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.isEmpty ? null : _titleCase(s);
  }

  static String _titleCase(String s) => s
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// A best-effort draft read from a spoken sentence. Any field may be null when
/// the words didn't yield a confident guess.
class ParsedVoiceExpense {
  final int? amountMinor;
  final String? category;
  final String? description;
  final String type;

  const ParsedVoiceExpense({
    this.amountMinor,
    this.category,
    this.description,
    this.type = DbConstants.txExpense,
  });

  /// An amount is the one field a voice entry can't be built without, so its
  /// absence is what marks the result unusable.
  bool get isEmpty => amountMinor == null;
}
