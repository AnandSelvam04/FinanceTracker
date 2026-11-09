part of 'sms_import.dart';

/// A draft transaction recovered from one SMS, before the user confirms it.
class ParsedSms {
  /// Minor units, always positive; [type] carries the direction.
  final int amount;

  /// Symbol of the currency [amount] is in — [SmsImport.rupee] for an ordinary
  /// alert, "\$" for "USD 12.99" — so a foreign charge is not filed as rupees.
  final String currency;

  /// [DbConstants.txExpense] or [DbConstants.txIncome].
  final String type;

  /// How the payment was made, when the message says ("UPI", "Credit Card",
  /// "Debit Card", "Cash"); null when it doesn't.
  final String? paymentMode;

  /// A credit that is money back from a merchant. Recorded as a negative
  /// expense so it offsets the purchase's category instead of reading as
  /// income.
  final bool isRefund;

  /// A cashback or reward credit — income, never a card bill payment.
  final bool isCashback;

  /// A debit whose wording says it paid a credit card's bill. Whether it
  /// becomes a transfer depends on the account it left (a charge *on* a card
  /// isn't a bill payment) — see [asBillPaymentFromBank].
  final bool isCardBillPayment;

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
    this.currency = SmsImport.rupee,
    required this.type,
    required this.description,
    required this.last4,
    this.toLast4,
    required this.date,
    required this.sender,
    required this.body,
    required this.sourceRef,
    this.alsoCoversRefs = const [],
    this.paymentMode,
    this.isRefund = false,
    this.isCashback = false,
    this.isCardBillPayment = false,
  });

  bool get isExpense => type == DbConstants.txExpense;
  bool get isTransfer => type == DbConstants.txTransfer;

  /// Whether the message reads like a credit card bill being paid, whichever
  /// way it was parsed — a transfer to a card that isn't added yet included.
  bool get readsLikeCardBill =>
      SmsImport._cardBillPayment.hasMatch(body.toLowerCase());

  /// The type the row is saved as: a refund is a (negative) expense.
  String get recordedType => isRefund ? DbConstants.txExpense : type;

  /// The amount the row is saved with: negative for a refund, so it takes the
  /// purchase back out of its category's total and the account's spend.
  int get signedAmount => isRefund ? -amount : amount;

  /// A credit that landed on a credit card and is neither a refund nor
  /// cashback: a payment of the card's bill. See [asCardPayment].
  bool get couldBeCardPayment =>
      type == DbConstants.txIncome && !isRefund && !isCashback;

  /// This credit re-read as a bill payment *into* the card it names: a
  /// transfer whose source (the bank account that paid) the message doesn't
  /// say, so the review screen asks for it. Booked as income it would inflate
  /// the month's income by the size of the card bill.
  ParsedSms asCardPayment() => ParsedSms(
        amount: amount,
        currency: currency,
        type: DbConstants.txTransfer,
        description: 'Card payment',
        last4: null,
        toLast4: last4,
        date: date,
        sender: sender,
        body: body,
        sourceRef: sourceRef,
        alsoCoversRefs: alsoCoversRefs,
      );

  /// This debit re-read as a payment from the bank account it names *into* a
  /// credit card: a transfer whose destination card the message didn't name,
  /// so the review screen asks for it. Booked as an expense it would count
  /// the card's purchases a second time.
  ParsedSms asBillPaymentFromBank() => ParsedSms(
        amount: amount,
        currency: currency,
        type: DbConstants.txTransfer,
        description: 'Card payment',
        last4: last4,
        toLast4: toLast4,
        date: date,
        sender: sender,
        body: body,
        sourceRef: sourceRef,
        alsoCoversRefs: alsoCoversRefs,
      );

  ParsedSms copyWith({
    String? type,
    String? description,
    String? toLast4,
    List<String>? alsoCoversRefs,
  }) =>
      ParsedSms(
        amount: amount,
        currency: currency,
        type: type ?? this.type,
        description: description ?? this.description,
        last4: last4,
        toLast4: toLast4 ?? this.toLast4,
        date: date,
        sender: sender,
        body: body,
        sourceRef: sourceRef,
        alsoCoversRefs: alsoCoversRefs ?? this.alsoCoversRefs,
        paymentMode: paymentMode,
        isRefund: isRefund,
        isCashback: isCashback,
        isCardBillPayment: isCardBillPayment,
      );

  /// The account whose [Account.last4] this message names, or null when the
  /// message carries no last-4 or no account claims it.
  ///
  /// Returns null when more than one account shares the digits, rather than
  /// guessing — the review screen asks instead.
  ///
  /// A message that names no account number at all — Scapia's "Your txn of
  /// ₹128.00 at Zepto on your Scapia Federal Visa credit card …" — is matched
  /// by name instead: see [_accountByName].
  Account? matchAccount(List<Account> accounts) {
    if (last4 == null && toLast4 == null) return _accountByName(accounts);
    return _accountFor(last4, accounts);
  }

  /// Words in an account's name that say nothing about which account it is.
  static const _genericNameWords = {
    'bank', 'card', 'cards', 'credit', 'debit', 'visa', 'master', //
    'mastercard', 'rupay', 'amex', 'upi', 'account', 'acct', 'savings',
    'saving', 'current', 'salary', 'wallet', 'cash', 'the', 'and', 'my',
    'main', 'personal', 'new', 'old', 'primary', 'secondary', 'premium',
    'platinum', 'gold', 'signature', 'select', 'classic',
  };

  /// The one account whose name shares the most distinctive words with the
  /// message ("Scapia" in "… on your Scapia Federal Visa credit card"), or
  /// null when none does or two tie. Generic words — "credit", "card",
  /// "bank", "visa" — don't count, and a message about a credit card only
  /// considers credit-card accounts when one of them matches.
  Account? _accountByName(List<Account> accounts) {
    final words = {
      for (final m in RegExp(r'[a-z0-9]+').allMatches(body.toLowerCase()))
        m.group(0)!
    };
    final scored = <(Account, int)>[];
    for (final a in accounts) {
      final tokens = {
        for (final m in RegExp(r'[a-z0-9]+').allMatches(a.name.toLowerCase()))
          m.group(0)!
      }..removeWhere((t) => t.length < 3 || _genericNameWords.contains(t));
      final hits = tokens.where(words.contains).length;
      if (hits > 0) scored.add((a, hits));
    }
    if (scored.isEmpty) return null;
    var pool = scored;
    if (RegExp(r'\bcredit\s*card\b').hasMatch(body.toLowerCase())) {
      final cards = scored.where((s) => s.$1.type == 'credit_card').toList();
      if (cards.isNotEmpty) pool = cards;
    }
    pool.sort((x, y) => y.$2.compareTo(x.$2));
    if (pool.length > 1 && pool[0].$2 == pool[1].$2) return null;
    return pool.first.$1;
  }

  /// The receiving account of a transfer, resolved the same way.
  Account? matchToAccount(List<Account> accounts) =>
      _accountFor(toLast4, accounts);

  static Account? _accountFor(String? digits, List<Account> accounts) {
    if (digits == null) return null;
    final matches = accounts
        .where((a) => SmsImport.sameAccountRef(a.last4, digits))
        .toList();
    return matches.length == 1 ? matches.first : null;
  }

  /// How many accounts carry the last digits this message names. More than
  /// one is why no account was picked, and the review screen says so.
  int accountsWithLast4(List<Account> accounts) => last4 == null
      ? 0
      : accounts.where((a) => SmsImport.sameAccountRef(a.last4, last4)).length;

  /// The payment mode to save: what the message said, else what the account
  /// implies (a charge on a credit-card account is a card payment), else
  /// "Other". Income carries none, as it always has.
  String paymentModeFor(Account? account) {
    if (!isExpense && !isRefund) return '';
    return paymentMode ??
        (account?.type == 'credit_card' ? 'Credit Card' : 'Other');
  }

  /// The draft as a transaction ready to insert. [description] overrides the
  /// parsed merchant/sender when the user edited it on the review screen, and
  /// [amount] the parsed figure when a foreign charge had to be re-entered in
  /// the account's currency. [paymentMode] defaults to the message's own.
  Expense toExpense({
    required int? accountId,
    required String category,
    int? toAccountId,
    String? description,
    int? amount,
    String? paymentMode,
    bool asSpending = false,
  }) {
    final positive = amount ?? this.amount;
    return Expense(
      description: description ?? this.description,
      amount: isRefund ? -positive : positive,
      date: date,
      category: category,
      paymentMode: paymentMode ?? paymentModeFor(null),
      type: asSpending ? DbConstants.txExpense : recordedType,
      accountId: accountId,
      toAccountId: isTransfer && !asSpending ? toAccountId : null,
      sourceRef: sourceRef,
    );
  }
}
