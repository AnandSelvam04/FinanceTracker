import '../models/account.dart';
import '../models/expense.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';

/// Turns bank transaction alerts into draft transactions.
///
/// Pure Dart on purpose: no plugin, no database, no Flutter. The SMS plugin
/// lives behind [SmsService] and hands raw strings to this file, so all of the
/// logic that can actually be wrong is unit-testable without a device.
///
/// Everything here is best-effort pattern matching against templates that
/// banks change without notice, so nothing it produces is posted
/// automatically — [SmsReviewScreen] shows the results for confirmation.
class SmsImport {
  SmsImport._();

  /// Wording that means money left the account.
  static final _debitWords = RegExp(
      r'\b(debited|debit|spent|withdrawn|withdrawal|paid|payment of|purchase|deducted|charged|transferred to)\b');

  /// Wording that means money arrived.
  static final _creditWords =
      RegExp(r'\b(credited|credit|received|deposited|refund(?:ed)?)\b');

  /// Messages that mention money but record no transaction. Checked first, so
  /// an OTP quoting an amount ("OTP for txn of Rs.500") never becomes a row.
  static final _notATransaction = RegExp(
      r'\b(otp|one[ -]?time password|password|verification code|will be debited|will be credited|has been requested|requesting|request for|failed|declined|reversed|due on|minimum amount due|statement is ready|e-?statement|offer|cashback offer|discount|sale|win|congratulations|apply now|click here|dear customer,? your bal)\b');

  /// A currency amount: "Rs.499.00", "INR 1,234.56", "₹499", "Rs 2,150/-".
  static final _amount = RegExp(
      r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
      caseSensitive: false);

  /// Words that mark the amount right after them as a balance or a limit
  /// rather than the transaction amount.
  static final _balanceContext = RegExp(
      r'\b(bal|balance|limit|available|avl|avbl|outstanding|o/s|unbilled|due)\b[^a-z]{0,12}$',
      caseSensitive: false);

  /// "A/c XX4821", "ac no. XXXX1234", "Card ending 5678", "card no xx1234".
  static final _last4Patterns = [
    RegExp(r'\ba/?c(?:count)?\.?\s*(?:no\.?|number)?\s*[x*\d]*?(\d{4})\b',
        caseSensitive: false),
    RegExp(
        r'\bcard\s*(?:no\.?|number|ending(?:\s*(?:with|in))?)?\s*[x*\d]*?(\d{4})\b',
        caseSensitive: false),
    // Bare masking, e.g. "XXXXXX1234" or "****5678".
    RegExp(r'[x*]{2,}\s*(\d{4})\b', caseSensitive: false),
  ];

  /// The counterparty: "to SWIGGY", "at AMAZON PAY", "towards NETFLIX".
  ///
  /// Case-sensitive because merchant names are conventionally upper-case, which
  /// keeps the match from running into ordinary prose. A dot is allowed only
  /// *between* word characters ("H.D.F.C"), never trailing — otherwise
  /// "to SWIGGY. Avl Bal Rs.12,340" swallows the balance clause, since those
  /// words are capitalised too.
  static const _merchantWord = r'[A-Z0-9][A-Za-z0-9&@_\-]*(?:\.[A-Za-z0-9&@_\-]+)*';
  static final _merchant = RegExp(
      r'\b(?:to|at|towards|for|in favour of)\s+'
      '($_merchantWord(?:\\s+$_merchantWord){0,3})');

  /// UPI handles, which are lower-case and so miss [_merchant].
  static final _vpa =
      RegExp(r'\b(?:vpa|upi(?:/| id)?)\s*:?\s*([\w.\-]{2,}@[a-z]{2,})',
          caseSensitive: false);

  /// "01-Aug-25", "01/08/2025", "01-08-25".
  static final _date = RegExp(
      r'\b(\d{1,2})[-/](\d{1,2}|[A-Za-z]{3})[-/](\d{2,4})\b',
      caseSensitive: false);

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// A stable id for one SMS, used to keep a rescan from re-importing it.
  ///
  /// Sender plus the message timestamp is already effectively unique; the body
  /// hash is folded in so that two alerts delivered in the same millisecond
  /// still differ. Must stay deterministic across app versions — it is
  /// persisted on the transaction row — so this uses an explicit FNV-1a rather
  /// than `String.hashCode`, which Dart does not guarantee between runs.
  static String sourceRefFor(String sender, DateTime receivedAt, String body) {
    return 'sms:${sender.toLowerCase()}:'
        '${receivedAt.millisecondsSinceEpoch}:${_fnv1a(body)}';
  }

  static String _fnv1a(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      // Keep it inside 32 bits; Dart ints are 64-bit and would otherwise grow.
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Parses one message, or returns null when it is not a transaction alert.
  ///
  /// [receivedAt] is the SMS timestamp, used as the transaction date when the
  /// body does not carry one of its own.
  static ParsedSms? parse({
    required String sender,
    required String body,
    required DateTime receivedAt,
  }) {
    final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return null;

    // "Credit card" / "debit card" name the instrument, not the direction.
    // Blanking them out first stops "spent on your Credit Card" reading as
    // income, which is the single most common way this goes wrong.
    final lower = text
        .toLowerCase()
        .replaceAll(RegExp(r'\b(credit|debit)\s*card\b'), ' card ');

    if (_notATransaction.hasMatch(lower)) return null;

    final type = _directionOf(lower);
    if (type == null) return null;

    final amount = _amountOf(text);
    if (amount == null) return null;

    return ParsedSms(
      amount: amount,
      type: type,
      description: _merchantOf(text) ?? _prettySender(sender),
      last4: _last4Of(text),
      date: _dateOf(text) ?? receivedAt,
      sender: sender,
      body: text,
      sourceRef: sourceRefFor(sender, receivedAt, body),
    );
  }

  /// Whichever direction word comes first wins. A message naming both ("debited
  /// from A/c X and credited to A/c Y") is one leg of a transfer; taking the
  /// earlier verb keeps it attached to the account it left.
  static String? _directionOf(String lower) {
    final debit = _debitWords.firstMatch(lower)?.start;
    final credit = _creditWords.firstMatch(lower)?.start;
    if (debit == null && credit == null) return null;
    if (debit == null) return DbConstants.txIncome;
    if (credit == null) return DbConstants.txExpense;
    return debit < credit ? DbConstants.txExpense : DbConstants.txIncome;
  }

  /// The first amount that is not a running balance or a credit limit.
  ///
  /// Alerts routinely quote two figures — "Rs.499 debited ... Avl Bal
  /// Rs.12,340" — and taking the wrong one silently books a transaction two
  /// orders of magnitude too large.
  static int? _amountOf(String text) {
    for (final match in _amount.allMatches(text)) {
      final before = text.substring(0, match.start);
      if (_balanceContext.hasMatch(before)) continue;
      final major = double.tryParse(match.group(1)!.replaceAll(',', ''));
      if (major == null || !isAmountInRange(major) || major <= 0) continue;
      return rupeesToMinor(major);
    }
    return null;
  }

  static String? _last4Of(String text) {
    for (final pattern in _last4Patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) return match.group(1);
    }
    return null;
  }

  static String? _merchantOf(String text) {
    final vpa = _vpa.firstMatch(text);
    if (vpa != null) return vpa.group(1);

    final match = _merchant.firstMatch(text);
    if (match == null) return null;
    var name = match.group(1)!.trim();
    // Strip a trailing "on"/"on 01-Aug-25" the greedy word run may have taken.
    name = name.replaceFirst(RegExp(r'\s+(on|dated)$', caseSensitive: false), '');
    if (name.isEmpty || name.length < 2) return null;
    return name;
  }

  static DateTime? _dateOf(String text) {
    final match = _date.firstMatch(text);
    if (match == null) return null;
    final day = int.tryParse(match.group(1)!);
    final rawMonth = match.group(2)!;
    final month =
        int.tryParse(rawMonth) ?? _months[rawMonth.toLowerCase().substring(0, 3)];
    var year = int.tryParse(match.group(3)!);
    if (day == null || month == null || year == null) return null;
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final parsed = DateTime(year, month, day);
    // DateTime rolls invalid days over (Feb 30 -> Mar 2); reject instead.
    if (parsed.day != day || parsed.month != month) return null;
    return parsed;
  }

  /// "VM-HDFCBK" / "AD-ICICIB-S" -> "HDFCBK". Sender ids are prefixed with the
  /// operator circle and suffixed with the message class.
  static String _prettySender(String sender) {
    final parts = sender.split('-').where((p) => p.length > 2).toList();
    return parts.isEmpty ? sender : parts.first.toUpperCase();
  }
}

/// A draft transaction recovered from one SMS, before the user confirms it.
class ParsedSms {
  /// Minor units, always positive; [type] carries the direction.
  final int amount;

  /// [DbConstants.txExpense] or [DbConstants.txIncome].
  final String type;

  /// Merchant or counterparty, falling back to the sender id.
  final String description;

  /// Last four digits of the account/card named in the message, if any.
  final String? last4;

  final DateTime date;
  final String sender;
  final String body;
  final String sourceRef;

  const ParsedSms({
    required this.amount,
    required this.type,
    required this.description,
    required this.last4,
    required this.date,
    required this.sender,
    required this.body,
    required this.sourceRef,
  });

  bool get isExpense => type == DbConstants.txExpense;

  /// The account whose [Account.last4] this message names, or null when the
  /// message carries no last-4 or no account claims it.
  ///
  /// Returns null when more than one account shares the digits, rather than
  /// guessing — the review screen asks instead.
  Account? matchAccount(List<Account> accounts) {
    final digits = last4;
    if (digits == null) return null;
    final matches = accounts.where((a) => a.last4 == digits).toList();
    return matches.length == 1 ? matches.first : null;
  }

  /// The draft as a transaction ready to insert.
  Expense toExpense({required int? accountId, required String category}) =>
      Expense(
        description: description,
        amount: amount,
        date: date,
        category: category,
        paymentMode: isExpense ? 'Other' : '',
        type: type,
        accountId: accountId,
        sourceRef: sourceRef,
      );
}
