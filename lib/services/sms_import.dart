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
      r'\b(debited|debit|spent|withdrawn|withdrawal|paid|payment of|purchase|deducted|charged|transferred|sent)\b');

  /// Wording that means money arrived.
  static final _creditWords =
      RegExp(r'\b(credited|credit|received|deposited|refund(?:ed)?)\b');

  /// Phrases that settle the direction on their own, checked before the
  /// positional rule below.
  ///
  /// "Payment of Rs.15,000 received on your Card XX5678" is a bill payment
  /// arriving at the card, but "payment of" comes first and would otherwise
  /// win — booking a repayment as another purchase and pushing the card
  /// further into debt instead of out of it.
  static final _strongCredit = RegExp(
      r'\b(payment\s+received|received\s+(?:on|in|towards|against)|credited\s+to|repayment\s+of)\b');

  /// Wording that means this is money moving between two accounts rather than
  /// spending. Used together with an explicit from/to pair of account numbers.
  static final _transferIntent = RegExp(
      r'\b(transferred|transfer|neft|imps|rtgs|fund\s*transfer|card\s*payment|bill\s*payment|towards\s+(?:your\s+)?(?:hdfc\s+|icici\s+|sbi\s+|axis\s+)?card)\b');

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

  /// Every account/card number mentioned: "A/c XX4821", "ac no. XXXX1234",
  /// "Card ending 5678", or bare masking like "XXXXXX1234".
  ///
  /// `\b(\d{4})\b` deliberately will not match inside a longer digit run, so
  /// reference numbers ("UPI/123456/...") are not mistaken for accounts.
  static final _accountRef = RegExp(
      r'\b(?:a/?c(?:count)?\.?|acct|card)\s*(?:no\.?|number|ending(?:\s*(?:with|in))?)?\s*[x*\d]{0,16}?(\d{4})\b'
      r'|[x*]{2,}\s*(\d{4})\b',
      caseSensitive: false);

  /// Prepositions that assign a role to the account reference that follows.
  ///
  /// Only the *nearest* one counts. "transferred from A/c XX4821 to A/c
  /// XX9012" puts both accounts after the word "from", so anything looser than
  /// nearest-wins files the destination as a second source and the transfer
  /// collapses back into an expense.
  static final _preposition = RegExp(
      r'\b(from|to|towards|into|in\s+favour\s+of|on)\b',
      caseSensitive: false);

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

    var type = _directionOf(lower);
    if (type == null) return null;

    final amount = _amountOf(text);
    if (amount == null) return null;

    final refs = _accountRefsOf(text, isCredit: type == DbConstants.txIncome);
    var last4 = refs.source;
    var toLast4 = refs.destination;

    // Money moving between two of the user's own accounts — a card bill paid
    // from a bank, an NEFT between banks. Recording it as an expense would
    // double-count: the card's purchases already hit the ledger, so the
    // repayment must move the balance, not add to the month's spending.
    final isTransfer = last4 != null &&
        toLast4 != null &&
        last4 != toLast4 &&
        (refs.rolesExplicit || _transferIntent.hasMatch(lower));
    if (isTransfer) {
      type = DbConstants.txTransfer;
    } else {
      // Only one side is known. An arriving payment names the account it
      // landed in, which belongs in last4 for a plain credit.
      if (last4 == null && toLast4 != null) {
        last4 = toLast4;
      }
      toLast4 = null;
    }

    return ParsedSms(
      amount: amount,
      type: type,
      description: isTransfer
          ? 'Transfer'
          : (_merchantOf(text) ?? _prettySender(sender)),
      last4: last4,
      toLast4: toLast4,
      date: _dateOf(text) ?? receivedAt,
      sender: sender,
      body: text,
      sourceRef: sourceRefFor(sender, receivedAt, body),
    );
  }

  /// An unambiguous credit phrase settles it; otherwise whichever direction
  /// word comes first wins. A message naming both ("debited from A/c X and
  /// credited to A/c Y") is a transfer, and taking the earlier verb keeps the
  /// source attached to the account the money left.
  static String? _directionOf(String lower) {
    if (_strongCredit.hasMatch(lower)) return DbConstants.txIncome;
    final debit = _debitWords.firstMatch(lower)?.start;
    final credit = _creditWords.firstMatch(lower)?.start;
    if (debit == null && credit == null) return null;
    if (debit == null) return DbConstants.txIncome;
    if (credit == null) return DbConstants.txExpense;
    return debit < credit ? DbConstants.txExpense : DbConstants.txIncome;
  }

  /// Splits the account numbers in a message into the one money left and the
  /// one it reached, by the preposition each is governed by.
  ///
  /// [isCredit] decides where an ungoverned or "on"-governed reference lands:
  /// "spent on card XX5678" is the source, while "received on card XX5678" is
  /// the destination.
  static ({String? source, String? destination, bool rolesExplicit})
      _accountRefsOf(String text, {required bool isCredit}) {
    String? source;
    String? destination;
    var sourceExplicit = false;
    var destExplicit = false;

    for (final match in _accountRef.allMatches(text)) {
      final digits = match.group(1) ?? match.group(2);
      if (digits == null) continue;
      final before = text.substring(0, match.start);
      final prepositions = _preposition.allMatches(before);
      final nearest = prepositions.isEmpty
          ? null
          : prepositions.last.group(1)!.toLowerCase();

      switch (nearest) {
        case 'from':
          source ??= digits;
          sourceExplicit = true;
        case 'to' || 'towards' || 'into':
          destination ??= digits;
          destExplicit = true;
        case String s when s.startsWith('in favour'):
          destination ??= digits;
          destExplicit = true;
        default:
          // "on" or nothing: "spent on card XX5678" is where the money came
          // from, "received on card XX5678" is where it landed.
          if (isCredit) {
            destination ??= digits;
          } else {
            source ??= digits;
          }
      }
    }

    return (
      source: source,
      destination: destination,
      rolesExplicit: sourceExplicit && destExplicit,
    );
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

  /// Folds the two alerts a single movement produces into one row.
  ///
  /// Moving money between accounts usually texts twice — the sending bank
  /// reports a debit, the receiving bank or card a credit. Imported as they
  /// stand that is one expense plus one income for a movement that changed no
  /// net worth at all. Two shapes are collapsed:
  ///
  ///  * a transfer that already names both accounts absorbs a single-sided
  ///    alert about either of them;
  ///  * a lone debit and a lone credit naming different accounts become one
  ///    transfer between them.
  ///
  /// Only same-amount messages inside [window] are paired, and the survivor
  /// carries the absorbed sourceRefs so a rescan does not re-offer them.
  static List<ParsedSms> collapseTransferPairs(
    List<ParsedSms> items, {
    Duration window = const Duration(days: 3),
  }) {
    final result = List<ParsedSms>.from(items);
    final dropped = <int>{};

    bool near(ParsedSms a, ParsedSms b) =>
        a.amount == b.amount &&
        a.date.difference(b.date).abs() <= window &&
        a.sourceRef != b.sourceRef;

    for (var i = 0; i < result.length; i++) {
      if (dropped.contains(i)) continue;
      for (var j = i + 1; j < result.length; j++) {
        if (dropped.contains(j)) continue;
        final a = result[i];
        final b = result[j];
        if (!near(a, b)) continue;

        // A two-sided transfer already describes the whole movement.
        final absorbed = _absorbs(a, b) ? j : (_absorbs(b, a) ? i : null);
        if (absorbed != null) {
          final keepIndex = absorbed == j ? i : j;
          result[keepIndex] = result[keepIndex].copyWith(alsoCoversRefs: [
            ...result[keepIndex].alsoCoversRefs,
            result[absorbed].sourceRef,
            ...result[absorbed].alsoCoversRefs,
          ]);
          dropped.add(absorbed);
          if (absorbed == i) break;
          continue;
        }

        // A bare debit here and a bare credit there are the two ends of one
        // transfer between them.
        final merged = _mergeLegs(a, b) ?? _mergeLegs(b, a);
        if (merged != null) {
          result[i] = merged;
          dropped.add(j);
        }
      }
    }

    return [
      for (var i = 0; i < result.length; i++)
        if (!dropped.contains(i)) result[i]
    ];
  }

  /// Whether [transfer] already covers the single account [other] names.
  static bool _absorbs(ParsedSms transfer, ParsedSms other) =>
      transfer.isTransfer &&
      !other.isTransfer &&
      other.last4 != null &&
      (other.last4 == transfer.last4 || other.last4 == transfer.toLast4);

  /// Combines a lone debit and a lone credit on different accounts.
  static ParsedSms? _mergeLegs(ParsedSms debit, ParsedSms credit) {
    if (debit.type != DbConstants.txExpense) return null;
    if (credit.type != DbConstants.txIncome) return null;
    if (debit.isTransfer || credit.isTransfer) return null;
    final from = debit.last4;
    final to = credit.last4;
    if (from == null || to == null || from == to) return null;
    return debit.copyWith(
      type: DbConstants.txTransfer,
      description: 'Transfer',
      toLast4: to,
      alsoCoversRefs: [
        ...debit.alsoCoversRefs,
        credit.sourceRef,
        ...credit.alsoCoversRefs,
      ],
    );
  }

  /// An already-recorded transaction that looks like [parsed] was entered by
  /// hand, or null when there is none.
  ///
  /// Only rows without a sourceRef are considered: anything imported from a
  /// message is already covered by the sourceRef check, and matching against
  /// those would flag a legitimate second purchase of the same amount.
  static Expense? findDuplicate(
    ParsedSms parsed,
    int? accountId,
    List<Expense> existing, {
    Duration window = const Duration(days: 2),
  }) {
    for (final e in existing) {
      if (e.sourceRef != null) continue;
      if (e.amount != parsed.amount || e.type != parsed.type) continue;
      if (e.date.difference(parsed.date).abs() > window) continue;
      // An unset account on either side is not evidence of a different
      // transaction, so it does not rule the match out.
      if (accountId != null && e.accountId != null && e.accountId != accountId) {
        continue;
      }
      return e;
    }
    return null;
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

  /// Last four digits of the account the money left (or, for a plain credit,
  /// the account it arrived in), if the message named one.
  final String? last4;

  /// For a transfer, the last four digits of the receiving account.
  final String? toLast4;

  final DateTime date;
  final String sender;
  final String body;
  final String sourceRef;

  /// Other messages this one stands in for — the mirror-image alert the second
  /// bank sent about the same movement. Marked as seen on import so a rescan
  /// does not offer the other half again.
  final List<String> alsoCoversRefs;

  const ParsedSms({
    required this.amount,
    required this.type,
    required this.description,
    required this.last4,
    this.toLast4,
    required this.date,
    required this.sender,
    required this.body,
    required this.sourceRef,
    this.alsoCoversRefs = const [],
  });

  bool get isExpense => type == DbConstants.txExpense;
  bool get isTransfer => type == DbConstants.txTransfer;

  ParsedSms copyWith({
    String? type,
    String? description,
    String? toLast4,
    List<String>? alsoCoversRefs,
  }) =>
      ParsedSms(
        amount: amount,
        type: type ?? this.type,
        description: description ?? this.description,
        last4: last4,
        toLast4: toLast4 ?? this.toLast4,
        date: date,
        sender: sender,
        body: body,
        sourceRef: sourceRef,
        alsoCoversRefs: alsoCoversRefs ?? this.alsoCoversRefs,
      );

  /// The account whose [Account.last4] this message names, or null when the
  /// message carries no last-4 or no account claims it.
  ///
  /// Returns null when more than one account shares the digits, rather than
  /// guessing — the review screen asks instead.
  Account? matchAccount(List<Account> accounts) =>
      _accountFor(last4, accounts);

  /// The receiving account of a transfer, resolved the same way.
  Account? matchToAccount(List<Account> accounts) =>
      _accountFor(toLast4, accounts);

  static Account? _accountFor(String? digits, List<Account> accounts) {
    if (digits == null) return null;
    final matches = accounts.where((a) => a.last4 == digits).toList();
    return matches.length == 1 ? matches.first : null;
  }

  /// The draft as a transaction ready to insert. [description] overrides the
  /// parsed merchant/sender when the user edited it on the review screen.
  Expense toExpense({
    required int? accountId,
    required String category,
    int? toAccountId,
    String? description,
  }) =>
      Expense(
        description: description ?? this.description,
        amount: amount,
        date: date,
        category: category,
        paymentMode: isExpense ? 'Other' : '',
        type: type,
        accountId: accountId,
        toAccountId: isTransfer ? toAccountId : null,
        sourceRef: sourceRef,
      );
}
