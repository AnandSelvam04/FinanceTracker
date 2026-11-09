import '../models/account.dart';
import '../models/expense.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';

export 'sms_matching.dart';

part 'parsed_sms.dart';

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
  static final _creditWords = RegExp(
      r'\b(credited|credit|received|deposited|refund(?:ed)?|reversed|reversal)\b');

  /// A completed card or UPI spend announced without any debit verb. Two banks
  /// do this:
  ///
  ///  * Scapia / Federal RuPay: "Your txn of ₹45.00 at R Muthukumar ... was
  ///    successful" — a "txn ... successful" with no verb.
  ///  * HDFC's UPI-on-card alert: "Txn Rs.72.00 On HDFC Bank Card 6955 At
  ///    q@ybl by UPI ..." and Federal's "Your txn of ₹842 at Flipkart on your
  ///    ... card ..." — a "txn" naming a card/UPI but no verb and no
  ///    "successful".
  ///
  /// Used only as a last resort when neither a debit nor a credit word is
  /// present: a genuine credit always names itself ("credited"/"received"), so
  /// a bare "txn" tied to a card/UPI/POS or a "successful" is a purchase.
  /// OTP, failed, and declined alerts also match "txn ... card", but they are
  /// dropped by [_notATransaction] before this is ever consulted.
  static final _cardOrUpiTxn = RegExp(
      r'\b(?:txn|transaction)\b.*\b(?:card|upi|vpa|pos|success(?:ful|fully)?)\b'
      r'|\b(?:card|upi|vpa|pos)\b.*\b(?:txn|transaction)\b');

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
  ///
  /// Only wording that can't appear in a genuine alert belongs here. Promo
  /// words ("offer", "sale", "win") used to be on this list too, and killed
  /// real debits from merchants such as "WIN MART" or "MEGA SALE"; they now
  /// count only when nothing in the message says money actually moved — see
  /// [_promo]. "reversed" moved off it as well: money reversed to the account
  /// is a refund to record, not noise.
  static final _notATransaction = RegExp(
      r'\b(otp|one[ -]?time password|password|verification code|will be (?:debited|credited|reversed|refunded)|has been requested|requesting|request for|failed|declined|due on|minimum amount due|statement is ready|e-?statement|apply now|click here|pre-?approved|dear customer,? your bal)\b');

  /// Marketing wording. Enough to drop a message only when [_moneyMoved]
  /// finds nothing: "Get Rs.500 off — sale ends today" is an advert, but
  /// "Rs.499 spent at MEGA SALE" is a purchase.
  static final _promo = RegExp(
      r'\b(offer|offers|discount|sale|win|won|winner|congratulations|voucher|coupon)\b');

  /// A completed movement of money, in the past tense.
  static final _moneyMoved = RegExp(
      r'\b(debited|credited|spent|withdrawn|paid|received|deposited|deducted|charged|transferred|sent|refunded|reversed)\b');

  /// A currency amount: "Rs.499.00", "INR 1,234.56", "₹499", "Rs 2,150/-",
  /// and the foreign charges a card abroad or on a foreign site texts about:
  /// "USD 12.99", "\$12.99", "EUR 20", "£5".
  ///
  /// The `\b` before the lettered markers keeps the "rs" inside an ordinary
  /// word from starting a match — without it "…for cars 5000 debited…" reads
  /// "rs 5000" as ₹5000. The symbols are not word characters, so they need no
  /// boundary. Group 1 is the currency marker, group 2 the figure.
  static final _amount = RegExp(
      r'(\brs\.?|\binr|₹|\b(?:usd|eur|gbp|aed|sgd|jpy|aud|cad)|[\$€£¥])'
      r'\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
      caseSensitive: false);

  /// The rupee, which every "Rs"/"INR"/"₹" alert is in.
  static const rupee = '₹';

  /// Currency markers mapped to the symbols accounts are held in (see
  /// SettingsProvider.currencyOptions), so a charge can be compared with the
  /// account it lands on. A code no account can be held in keeps its own name
  /// and so never matches — the review screen then asks for the ₹ amount.
  static const _currencySymbols = {
    'rs': rupee, 'rs.': rupee, 'inr': rupee, '₹': rupee, //
    'usd': r'$', r'$': r'$', 'eur': '€', '€': '€', 'gbp': '£', '£': '£',
    'jpy': '¥', '¥': '¥', 'aud': r'A$', 'cad': r'C$',
  };

  /// A refund of an earlier purchase. Money back from a merchant is spending
  /// undone, not income, so it is filed against the purchase's category.
  static final _refund = RegExp(r'\b(refund(?:ed)?|reversed|reversal)\b');

  /// Cashback and rewards credited to a card: real money in, but not a
  /// payment of the bill, so it stays income.
  static final _cashback = RegExp(r'\b(cashback|cash back|reward|rewards)\b');

  /// Wording that marks a debit as a purchase made *with* a card, which no
  /// card-bill phrase elsewhere in the message turns into a bill payment.
  static final _purchase = RegExp(r'\b(spent|purchase|shopping)\b');

  /// A debit that pays a credit card's bill: "towards Credit Card bill",
  /// "HDFC Credit Card payment", "paid to CRED". Banks often text this without
  /// the card's number, so it can't be told apart as a transfer from the
  /// account numbers alone — and booked as an expense it counts the card's
  /// spending a second time. Checked on the text *before* "credit card" is
  /// blanked out for direction-finding, since here it is the whole point.
  ///
  /// "card payment" alone is not enough ("card payment of Rs.500 at AMAZON"
  /// is a purchase), so the card has to be named as a credit card or "CC", or
  /// be the object of a bill/dues/outstanding.
  static final _cardBillPayment = RegExp(
      r'\b(?:credit\s*card|cc)\s*(?:bill|dues?|payment|outstanding)\b'
      r'|\bcard\s*(?:bill|dues|outstanding)\b'
      r'|\b(?:to|towards|for)\s+(?:your\s+)?(?:[a-z]+\s+){0,2}(?:credit\s*card|cc)\b'
      r'|\bcred(?:\.club)?\b');

  /// Words that mark the amount right after them as a balance or a limit
  /// rather than the transaction amount.
  static final _balanceContext = RegExp(
      r'\b(bal|balance|limit|available|avl|avbl|outstanding|o/s|unbilled|due)\b[^a-z]{0,12}$',
      caseSensitive: false);

  /// Every account/card number mentioned: "A/c XX4821", "ac no. XXXX1234",
  /// "Card ending 5678", or bare masking like "XXXXXX1234".
  ///
  /// Three digits are accepted as well as four: ICICI masks its accounts as
  /// "Acct XX123". Four are preferred when both would fit, and
  /// [SmsImport.sameAccountRef] lets a three-digit reference match an account
  /// whose last four end in it.
  ///
  /// The trailing `\b` deliberately will not match inside a longer digit run,
  /// so reference numbers ("UPI/123456/...") are not mistaken for accounts.
  static final _accountRef = RegExp(
      r'\b(?:a/?c(?:count)?\.?|acct|card)\s*(?:no\.?|number|ending(?:\s*(?:with|in))?)?\s*[x*\d]{0,16}?(\d{3,4})\b'
      r'|[x*]{2,}\s*(\d{3,4})\b',
      caseSensitive: false);

  /// Whether two masked account references name the same account: equal, or
  /// a three-digit one ("XX123", ICICI's masking) that the other ends in.
  static bool sameAccountRef(String? a, String? b) {
    if (a == null || b == null) return false;
    if (a == b) return true;
    if (a.length == 3 && b.length > 3) return b.endsWith(a);
    if (b.length == 3 && a.length > 3) return a.endsWith(b);
    return false;
  }

  /// Whether a message from [sender] cannot be a bank alert and should not be
  /// read at all.
  ///
  /// Banks text from registered headers ("VM-HDFCBK", "JD-ICICIT-S") or short
  /// codes, never from an ordinary phone number — a friend's "I sent you Rs
  /// 500" comes from one of those and is not a transaction on this phone. A
  /// "-P" suffix is TRAI's marker for promotional traffic, which carries
  /// offers rather than alerts.
  static bool isNonBankSender(String sender) {
    final s = sender.replaceAll(RegExp(r'[\s()-]'), '');
    if (RegExp(r'^\+?\d{10,}$').hasMatch(s)) return true;
    return RegExp(r'-p$', caseSensitive: false).hasMatch(sender.trim());
  }

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
  ///
  /// The preposition itself may be capitalised — HDFC writes "Spent Rs.705
  /// On HDFC Bank Card 9812 At PTM*FLIPKART M" — and a `*` may sit inside a
  /// word, as payment gateways prefix the merchant ("PTM*", "RAZ*"; see
  /// [_gatewayPrefix]).
  static const _merchantWord =
      r'[A-Z0-9][A-Za-z0-9&@_*\-]*(?:\.[A-Za-z0-9&@_*\-]+)*';
  static final _merchant =
      RegExp(r'\b(?:[Tt]o|[Aa]t|[Tt]owards|[Ff]or|[Ii]n [Ff]avour [Oo]f)\s+'
          '($_merchantWord(?:\\s+$_merchantWord){0,3})');

  /// A payment gateway's tag in front of the merchant: Paytm "PTM*", PayU,
  /// Razorpay, CCAvenue, BillDesk. Stripped so "PTM*FLIPKART M" files as
  /// "FLIPKART M" and matches Flipkart's earlier rows.
  static final _gatewayPrefix = RegExp(
      r'^(?:PTM|PAYTM|PYTM|PAYU|PYU|RAZ|RZP|RAZORPAY|CCA|CCAV|BDK|BILLDESK|PG|IND)\*\s*',
      caseSensitive: false);

  /// Footer wording that a capitalised "To"/"For" introduces — "Not you? To
  /// Block+Reissue Call …", "For queries …" — and that is never the payee.
  static final _footerWord = RegExp(
      r'^(?:block|report|call|dispute|know|check|queries|query|help|more|details|stop|unsubscribe|any)\b',
      caseSensitive: false);

  /// The payee named as the account that was credited, after a clause break:
  /// ICICI's "Acct XX123 debited for Rs 240.00 on 28-Oct-25; SWIGGY
  /// credited." Only consulted for debits — in a credit, "… credited" is the
  /// user's own account.
  static final _creditedPayee = RegExp(
      '[;.]\\s*($_merchantWord(?:\\s+$_merchantWord){0,3})\\s+credited\\b');

  /// A name that is really a currency amount: "for Rs 240.00" would otherwise
  /// give "Rs 240.00" as the merchant, since "Rs" is capitalised.
  static final _currencyLead = RegExp(
      r'^(?:rs\.?|inr|usd|eur|gbp|aed|sgd|jpy|aud|cad)\b',
      caseSensitive: false);

  /// Whether [name] can be a payee: two characters or more, at least one
  /// letter (so "to 7308080808" — a shortcode — is not one), and not an
  /// amount.
  static bool _isPayeeName(String name) =>
      name.length >= 2 &&
      RegExp(r'[A-Za-z]').hasMatch(name) &&
      !_currencyLead.hasMatch(name);

  /// UPI handles, which are lower-case and so miss [_merchant].
  static final _vpa = RegExp(
      r'\b(?:vpa|upi(?:/| id)?)\s*:?\s*([\w.\-]{2,}@[a-z]{2,})',
      caseSensitive: false);

  /// A bare UPI handle with no "UPI:"/"VPA:" label in front of it, e.g. the
  /// "At q233098266@ybl" in an HDFC card+UPI alert. Distinguished from an email
  /// address by requiring the part after '@' to be letters only and not be
  /// followed by a dot, so "shop@okhdfcbank" matches but "user@gmail.com" does
  /// not (an email's domain has a dot).
  static final _bareVpa =
      RegExp(r'\b([\w.\-]{2,}@[a-z]{2,})(?![\w.])', caseSensitive: false);

  /// "01-Aug-25", "01/08/2025", "01-08-25".
  static final _date = RegExp(
      r'\b(\d{1,2})[-/](\d{1,2}|[A-Za-z]{3})[-/](\d{2,4})\b',
      caseSensitive: false);

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static const _smsRefPrefix = 'sms:';

  /// Whether [ref] marks a transaction imported from an SMS (as opposed to a
  /// CSV row or one entered by hand).
  static bool isSmsSourceRef(String? ref) =>
      ref?.startsWith(_smsRefPrefix) ?? false;

  /// A stable id for one SMS, used to keep a rescan from re-importing it.
  ///
  /// Sender plus the message timestamp is already effectively unique; the body
  /// hash is folded in so that two alerts delivered in the same millisecond
  /// still differ. Must stay deterministic across app versions — it is
  /// persisted on the transaction row — so this uses an explicit FNV-1a rather
  /// than `String.hashCode`, which Dart does not guarantee between runs.
  static String sourceRefFor(String sender, DateTime receivedAt, String body) {
    return '$_smsRefPrefix${sender.toLowerCase()}:'
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
    final raw = text.toLowerCase();
    final lower =
        raw.replaceAll(RegExp(r'\b(credit|debit)\s*card\b'), ' card ');

    if (_notATransaction.hasMatch(lower)) return null;
    if (_promo.hasMatch(lower) && !_moneyMoved.hasMatch(lower)) return null;

    var type = _directionOf(lower);
    if (type == null) return null;

    final money = _amountOf(text);
    if (money == null) return null;

    final refs = _accountRefsOf(text, isCredit: type == DbConstants.txIncome);
    var last4 = refs.source;
    var toLast4 = refs.destination;

    // Money moving between two of the user's own accounts — a card bill paid
    // from a bank, an NEFT between banks. Recording it as an expense would
    // double-count: the card's purchases already hit the ledger, so the
    // repayment must move the balance, not add to the month's spending.
    final isTransfer = last4 != null &&
        toLast4 != null &&
        !sameAccountRef(last4, toLast4) &&
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

    final refund = type == DbConstants.txIncome && _refund.hasMatch(lower);
    return ParsedSms(
      amount: money.amount,
      currency: money.currency,
      type: type,
      description: isTransfer
          ? 'Transfer'
          : (_merchantOf(text, debit: type == DbConstants.txExpense) ??
              (refund ? _refundMerchantOf(text) : null) ??
              _prettySender(sender)),
      last4: last4,
      toLast4: toLast4,
      date: plausibleDate(_dateOf(text), receivedAt),
      sender: sender,
      body: text,
      sourceRef: sourceRefFor(sender, receivedAt, body),
      paymentMode: paymentModeOf(raw),
      isRefund: refund,
      isCashback: type == DbConstants.txIncome && _cashback.hasMatch(lower),
      isCardBillPayment: type == DbConstants.txExpense &&
          _cardBillPayment.hasMatch(raw) &&
          !_purchase.hasMatch(raw),
    );
  }

  /// "Avl Lmt: Rs 1,85,000.00", "Available limit is INR 1,23,456.78", "Avbl
  /// Cr Lmt INR 50,000" — the credit limit still free on the card, as the
  /// card's alerts quote it after each purchase or payment.
  static final _availableLimit = RegExp(
      r'\b(?:avl|avbl|avail|available)\.?\s*(?:cr\.?|credit)?\s*(?:lmt|limit)\b'
      r'[\s:.\-]*(?:is\s*)?(?:rs\.?|inr|₹)?\s*([\d,]+(?:\.\d{1,2})?)',
      caseSensitive: false);

  /// "Reward Points balance: 12,345", "Your reward point bal is 4,560",
  /// "Balance reward points 890" — a card's points balance.
  static final _rewardBalance = RegExp(
      r'\breward\s*points?\s*(?:balance|bal)\b[^0-9]{0,15}([\d,]+)'
      r'|\b(?:balance|bal)\.?\s*(?:of\s*)?reward\s*points?\b[^0-9]{0,15}([\d,]+)',
      caseSensitive: false);

  /// The reward points balance a card message quotes, and the card it names.
  /// Null when it quotes none ("you earned 50 points" is not a balance).
  static ({int points, String? last4})? rewardPointsOf(String body) {
    final text = body.replaceAll(RegExp(r'\s+'), ' ');
    final m = _rewardBalance.firstMatch(text);
    if (m == null) return null;
    final points =
        int.tryParse((m.group(1) ?? m.group(2))!.replaceAll(',', ''));
    if (points == null) return null;
    String? last4;
    for (final r in _accountRef.allMatches(text)) {
      last4 ??= r.group(1) ?? r.group(2);
    }
    return (points: points, last4: last4);
  }

  /// The available credit limit a card alert quotes, and the card it names
  /// (its last digits, when the message gives them). Null when the message
  /// quotes no available limit. Works on any message, transaction or not.
  static ({int amount, String? last4})? availableLimitOf(String body) {
    final text = body.replaceAll(RegExp(r'\s+'), ' ');
    final m = _availableLimit.firstMatch(text);
    if (m == null) return null;
    final major = double.tryParse(m.group(1)!.replaceAll(',', ''));
    if (major == null || major < 0 || !isAmountInRange(major)) return null;
    String? last4;
    for (final r in _accountRef.allMatches(text)) {
      if (r.start >= m.start) break;
      last4 ??= r.group(1) ?? r.group(2);
    }
    return (amount: rupeesToMinor(major), last4: last4);
  }

  /// How the money was paid, when the message says so: a UPI payment (even one
  /// made with a RuPay credit card, the way the Add Expense screen files it),
  /// a named credit or debit card, or an ATM withdrawal in cash. Null when the
  /// message doesn't say — the review screen then goes by the account's type.
  ///
  /// [raw] is the lower-cased message *before* "credit card"/"debit card" are
  /// blanked out for direction-finding, since here they are the whole point.
  static String? paymentModeOf(String raw) {
    if (RegExp(r'\b(upi|vpa)\b').hasMatch(raw) || _bareVpa.hasMatch(raw)) {
      return 'UPI';
    }
    if (RegExp(r'\bcredit\s*card\b').hasMatch(raw)) return 'Credit Card';
    if (RegExp(r'\bdebit\s*card\b').hasMatch(raw)) return 'Debit Card';
    if (RegExp(r'\b(atm|cash withdrawal)\b').hasMatch(raw)) return 'Cash';
    return null;
  }

  /// An unambiguous credit phrase settles it; otherwise whichever direction
  /// word comes first wins. A message naming both ("debited from A/c X and
  /// credited to A/c Y") is a transfer, and taking the earlier verb keeps the
  /// source attached to the account the money left.
  static String? _directionOf(String lower) {
    if (_strongCredit.hasMatch(lower)) return DbConstants.txIncome;
    final debit = _debitWords.firstMatch(lower)?.start;
    final credit = _creditWords.firstMatch(lower)?.start;
    if (debit == null && credit == null) {
      // No direction verb at all — accept a card/UPI spend that names itself
      // only as a "txn" (HDFC card+UPI alerts, Scapia/Federal "successful"),
      // otherwise it is not a transaction alert we can place.
      return _cardOrUpiTxn.hasMatch(lower) ? DbConstants.txExpense : null;
    }
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
  static ({int amount, String currency})? _amountOf(String text) {
    for (final match in _amount.allMatches(text)) {
      final before = text.substring(0, match.start);
      if (_balanceContext.hasMatch(before)) continue;
      final major = double.tryParse(match.group(2)!.replaceAll(',', ''));
      if (major == null || !isAmountInRange(major) || major <= 0) continue;
      final marker = match.group(1)!.toLowerCase();
      return (
        amount: rupeesToMinor(major),
        currency: _currencySymbols[marker] ?? marker.toUpperCase(),
      );
    }
    return null;
  }

  static String? _merchantOf(String text, {required bool debit}) {
    final vpa = _vpa.firstMatch(text);
    if (vpa != null) return vpa.group(1);

    // A bare UPI handle ("At q@ybl") is a reliable payee even without a label,
    // and is preferred over the generic word run below — which can otherwise
    // latch onto a trailing shortcode ("... to 7308080808").
    final bare = _bareVpa.firstMatch(text);
    if (bare != null) return bare.group(1);

    if (debit) {
      for (final match in _creditedPayee.allMatches(text)) {
        final name = match.group(1)!.trim();
        if (_isPayeeName(name)) return name;
      }
    }

    for (final match in _merchant.allMatches(text)) {
      var name = match.group(1)!.trim();
      // Strip a trailing "on"/"On 2026-11-06" the greedy word run may have
      // taken.
      name = name.replaceFirst(
          RegExp(r'\s+(?:on|dated)(?:\s+\d\S*)?$', caseSensitive: false), '');
      name = name.replaceFirst(_gatewayPrefix, '').replaceAll('*', ' ').trim();
      if (_footerWord.hasMatch(name)) continue;
      if (_isPayeeName(name)) return name;
    }
    return null;
  }

  /// The merchant a refund came back from: "Refund of Rs.500 … from AMAZON".
  /// Only tried for refunds — in other credits "from" names the sender's
  /// bank or a person, which the sender id fallback describes as well.
  static String? _refundMerchantOf(String text) {
    final match =
        RegExp('\\b(?:from|by)\\s+($_merchantWord(?:\\s+$_merchantWord){0,3})')
            .firstMatch(text);
    if (match == null) return null;
    final name = match
        .group(1)!
        .replaceFirst(RegExp(r'\s+(on|dated)$', caseSensitive: false), '')
        .trim();
    return _isPayeeName(name) ? name : null;
  }

  /// How far before the SMS arrived a date in its body is still taken as the
  /// transaction date. Banks text within minutes or days; anything older is
  /// some other date in the message.
  static const plausibleLookback = Duration(days: 45);

  /// The date in the body if it could be when the money moved, else the day
  /// the SMS arrived. A payment can't happen after its own alert, so a later
  /// date is a due date, a day/month read the wrong way round, or a typo —
  /// and filing it there put the row in a future month where no budget or
  /// summary for this month counted it.
  static DateTime plausibleDate(DateTime? parsed, DateTime receivedAt) {
    if (parsed == null) return receivedAt;
    final received =
        DateTime(receivedAt.year, receivedAt.month, receivedAt.day);
    // A day's slack for time zones and alerts sent just after midnight.
    final nextDay = DateTime(received.year, received.month, received.day + 1);
    if (parsed.isAfter(nextDay)) {
      return receivedAt;
    }
    if (parsed.isBefore(received.subtract(plausibleLookback))) {
      return receivedAt;
    }
    // The body gives a day, not a time. On the day the SMS arrived, the
    // arrival time is the best time there is; filing it at midnight put the
    // purchase before everything else that day.
    if (parsed.year == received.year &&
        parsed.month == received.month &&
        parsed.day == received.day) {
      return receivedAt;
    }
    return parsed;
  }

  /// The first date the message carries, in any of the shapes banks use:
  /// "01-Aug-25", "01/08/2025", "01 Aug 2025", "01Aug25", "Aug 01, 2025" and
  /// ISO "2025-08-01". Whichever comes first in the text wins.
  static DateTime? _dateOf(String text) {
    final found = <(int, DateTime?)>[];
    void collect(RegExp pattern, DateTime? Function(RegExpMatch m) read) {
      final m = pattern.firstMatch(text);
      if (m != null) found.add((m.start, read(m)));
    }

    collect(_date, (m) => _validDate(m.group(3)!, m.group(2)!, m.group(1)!));
    collect(_isoDate, (m) => _validDate(m.group(1)!, m.group(2)!, m.group(3)!));
    collect(
        _spacedDate, (m) => _validDate(m.group(3)!, m.group(2)!, m.group(1)!));
    collect(_monthFirstDate,
        (m) => _validDate(m.group(3)!, m.group(1)!, m.group(2)!));
    found.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (_, date) in found) {
      if (date != null) return date;
    }
    return null;
  }

  /// ISO "2025-08-01", as some card issuers write it.
  static final _isoDate = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b');

  /// "01 Aug 2025", "1 August, 2025", "01Aug25".
  static final _spacedDate = RegExp(
      r'\b(\d{1,2})\s*([A-Za-z]{3,9})\.?,?\s*(\d{4}|\d{2})\b',
      caseSensitive: false);

  /// "Aug 01, 2025", "August 1 2025".
  static final _monthFirstDate = RegExp(
      r'\b([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b',
      caseSensitive: false);

  static const _fullMonths = [
    'january', 'february', 'march', 'april', 'may', 'june', //
    'july', 'august', 'september', 'october', 'november', 'december',
  ];

  /// A month given as a number, a three-letter abbreviation, "Sept", or the
  /// full name — never just any word that starts like one ("Market").
  static int? _monthOf(String raw) {
    final n = int.tryParse(raw);
    if (n != null) return n;
    final lower = raw.toLowerCase();
    if (lower.length < 3) return null;
    final month = _months[lower.substring(0, 3)];
    if (month == null) return null;
    final ok = lower.length == 3 ||
        lower == _fullMonths[month - 1] ||
        (month == 9 && lower == 'sept');
    return ok ? month : null;
  }

  static DateTime? _validDate(String rawYear, String rawMonth, String rawDay) {
    final day = int.tryParse(rawDay);
    final month = _monthOf(rawMonth);
    var year = int.tryParse(rawYear);
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
