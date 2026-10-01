import 'dart:io';

import 'package:another_telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/expense.dart';
import '../models/investment.dart';
import '../services/db_service.dart';
import '../utils/app_logger.dart';
import '../utils/currency_format.dart';
import 'category_memory.dart';
import 'merchant_categories.dart';
import 'sms_import.dart';

/// Reads the device SMS inbox and hands each message to [SmsImport].
///
/// This is the only file that touches the telephony plugin, so everything that
/// can be unit-tested lives in [SmsImport] instead. Nothing here posts a
/// transaction — [scan] returns candidates for the review queue.
class SmsService {
  SmsService._();

  /// How far back a scan looks when there is no earlier review to go from.
  ///
  /// Deliberately short: it keeps the first run from dumping months of history
  /// into the queue. After that the review screen scans from the last time the
  /// queue was cleared instead (see [scanStartSince]), so a gap of a week
  /// between visits no longer loses the week's alerts.
  static const defaultWindow = Duration(days: 2);

  /// The furthest back a "since last review" scan reaches, however long ago
  /// that review was — the same cap as the widest preset, so coming back after
  /// months doesn't bury the queue under a season of alerts.
  static const maxCatchUp = Duration(days: 30);

  /// Overlap kept before the last review, for alerts that arrive late (banks
  /// sometimes text hours after the payment). Anything already imported or
  /// dismissed is filtered out anyway, so the overlap costs nothing.
  static const _reviewOverlap = Duration(days: 1);

  static const _kReviewedThrough = 'smsReviewedThrough';
  static const _kIgnoredMerchants = 'smsIgnoredMerchants';

  /// Where a default scan starts: a day before [reviewedThrough] — the moment
  /// the review queue was last left empty — but never less than
  /// [defaultWindow] ago nor more than [maxCatchUp] ago. With no review yet,
  /// just [defaultWindow].
  static DateTime scanStartSince(DateTime? reviewedThrough, DateTime now) {
    final shortest = now.subtract(defaultWindow);
    if (reviewedThrough == null) return shortest;
    final earliest = now.subtract(maxCatchUp);
    final start = reviewedThrough.subtract(_reviewOverlap);
    if (start.isAfter(shortest)) return shortest;
    if (start.isBefore(earliest)) return earliest;
    return start;
  }

  /// When the review queue was last left empty, or null if it never was.
  ///
  /// Recorded only once every found message has been imported or dismissed:
  /// moving it forward on every scan would skip messages the user looked at
  /// but left for later.
  static Future<DateTime?> reviewedThrough() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_kReviewedThrough);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (e, s) {
      AppLogger.error('Reading the SMS review mark failed', e, s);
      return null;
    }
  }

  /// Records that every message up to [at] has been dealt with. Never moves the
  /// mark backwards, so a narrow custom-range scan can't undo a wider one.
  static Future<void> markReviewedThrough(DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(_kReviewedThrough);
      final ms = at.millisecondsSinceEpoch;
      if (current != null && current >= ms) return;
      await prefs.setInt(_kReviewedThrough, ms);
    } catch (e, s) {
      AppLogger.error('Saving the SMS review mark failed', e, s);
    }
  }

  /// Merchants the user chose to never be offered again, as
  /// [CategoryMemory.merchantKey]s.
  static Future<Set<String>> ignoredMerchants() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_kIgnoredMerchants) ?? const []).toSet();
    } catch (e, s) {
      AppLogger.error('Reading ignored SMS merchants failed', e, s);
      return <String>{};
    }
  }

  static Future<void> _saveIgnoredMerchants(Set<String> keys) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kIgnoredMerchants, keys.toList()..sort());
    } catch (e, s) {
      AppLogger.error('Saving ignored SMS merchants failed', e, s);
    }
  }

  /// Stops offering messages from the merchant named [description] (a wallet
  /// top-up, an EMI already tracked as a recurring rule). Returns the key it
  /// was stored under, or null when the name has nothing to key on.
  static Future<String?> ignoreMerchant(String description) async {
    final key = CategoryMemory.merchantKey(description);
    if (key.isEmpty) return null;
    await _saveIgnoredMerchants({...await ignoredMerchants(), key});
    return key;
  }

  /// Offers messages from the merchant stored under [key] again.
  static Future<void> unignoreMerchant(String key) async {
    final keys = await ignoredMerchants();
    if (keys.remove(key)) await _saveIgnoredMerchants(keys);
  }

  /// Whether [parsed] comes from a merchant in [ignored]. A transfer names no
  /// merchant, so it is never hidden this way.
  static bool isIgnored(ParsedSms parsed, Set<String> ignored) =>
      !parsed.isTransfer &&
      ignored.contains(CategoryMemory.merchantKey(parsed.description));

  /// Whether the user has switched SMS import on in Settings. Mirrored here
  /// from SettingsProvider so the service can refuse to read the inbox
  /// without reaching into the widget tree — see [SettingsProvider].
  static bool enabled = false;

  /// Set by tests to stand in for the plugin. Production leaves this null.
  static Future<List<RawSms>> Function()? inboxOverride;

  /// Whether SMS import can work at all here. Android-only: the plugin has no
  /// implementation on other platforms, and reading another app's inbox is not
  /// a thing iOS permits.
  static bool get isSupported {
    if (inboxOverride != null) return true;
    try {
      return Platform.isAndroid;
    } on UnsupportedError {
      // Platform throws under the test harness rather than reporting a host OS.
      return false;
    }
  }

  /// Asks for READ_SMS, returning whether it was granted. Safe to call again;
  /// Android shows the dialog only until the user has answered it.
  static Future<bool> requestPermission() async {
    if (!isSupported || !enabled) return false;
    // A test's stand-in inbox needs no permission (see [isSupported]).
    if (inboxOverride != null) return true;
    try {
      return await Telephony.instance.requestSmsPermissions ?? false;
    } catch (e, s) {
      AppLogger.error('SMS permission request failed', e, s);
      return false;
    }
  }

  /// Parses recent inbox messages into candidate transactions.
  ///
  /// Drops anything already imported or previously dismissed, so calling this
  /// repeatedly never re-offers the same message. Newest first.
  ///
  /// The scanned window is the last [window] by default. Pass [from] (and
  /// optionally [to]) to scan an explicit date range instead — the review
  /// screen uses this to scan since the last review, and so a user can pull in
  /// older messages. Pass [includeDismissed] to surface messages the user
  /// rejected earlier (and those from ignored merchants), so a wrongly
  /// dismissed one can be recovered.
  static Future<List<ParsedSms>> scan({
    Duration window = defaultWindow,
    DateTime? now,
    DateTime? from,
    DateTime? to,
    bool includeDismissed = false,
  }) async {
    // Checked here as well as at the permission gate, so no code path can read
    // the inbox while the setting is off.
    if (!isSupported || !enabled) return const [];
    final lower = from ?? (now ?? DateTime.now()).subtract(window);
    final seen =
        await DBService().existingSourceRefs(includeIgnored: !includeDismissed);
    final ignored =
        includeDismissed ? const <String>{} : await ignoredMerchants();

    final parsed = <ParsedSms>[];
    for (final sms in await _inbox()) {
      if (sms.receivedAt.isBefore(lower)) continue;
      if (to != null && sms.receivedAt.isAfter(to)) continue;
      final candidate = SmsImport.parse(
        sender: sms.sender,
        body: sms.body,
        receivedAt: sms.receivedAt,
      );
      if (candidate == null || seen.contains(candidate.sourceRef)) continue;
      if (isIgnored(candidate, ignored)) continue;
      parsed.add(candidate);
    }
    // Pair up the two alerts one movement produces before sorting, so a card
    // payment shows as a single transfer rather than a debit and a credit.
    final collapsed = SmsImport.collapseTransferPairs(parsed)
      ..sort((a, b) => b.date.compareTo(a.date));
    return collapsed;
  }

  /// How many new transaction alerts are waiting since the last review, for
  /// the badge on the dashboard's Import SMS shortcut. Zero when import is off
  /// or the permission hasn't been granted: this never asks for it (a refused
  /// inbox read is caught in [_inbox] and reads as empty), so opening the
  /// dashboard can't pop a permission dialog.
  static Future<int> pendingCount({DateTime? now}) async {
    if (!isSupported || !enabled) return 0;
    final at = now ?? DateTime.now();
    final found =
        await scan(now: at, from: scanStartSince(await reviewedThrough(), at));
    return found.length;
  }

  /// Reads raw inbox rows, translating the plugin's message type into
  /// [RawSms] so nothing above this line depends on the plugin's classes.
  static Future<List<RawSms>> _inbox() async {
    final override = inboxOverride;
    if (override != null) return override();
    try {
      final messages = await Telephony.instance.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      );
      return [
        for (final m in messages)
          if (m.body != null && m.body!.isNotEmpty)
            RawSms(
              sender: m.address ?? '',
              body: m.body!,
              receivedAt: DateTime.fromMillisecondsSinceEpoch(
                  m.date ?? DateTime.now().millisecondsSinceEpoch),
            ),
      ];
    } catch (e, s) {
      // A revoked permission or an OEM that blocks inbox reads surfaces here.
      // An empty scan reads as "nothing found", which is the right outcome.
      AppLogger.error('Reading the SMS inbox failed', e, s);
      return const [];
    }
  }
}

/// One inbox message, decoupled from the plugin's own type.
class RawSms {
  final String sender;
  final String body;
  final DateTime receivedAt;

  const RawSms({
    required this.sender,
    required this.body,
    required this.receivedAt,
  });
}

/// A candidate paired with the choices the review screen lets the user change
/// before it is posted.
class SmsDraft {
  final ParsedSms parsed;
  int? accountId;

  /// Receiving account, for a transfer only.
  int? toAccountId;
  String category;
  bool selected;

  /// The label this row is saved under. Starts from the parsed merchant/sender
  /// but is editable on the review screen, so a cryptic "UPI/..." can be given
  /// a name the user recognises before it is posted.
  String description;

  /// How the payment was made. Starts from the message ("by UPI") or, failing
  /// that, the matched account's type; editable on the review screen.
  String paymentMode;

  /// The amount in the account's currency, entered on the review screen when
  /// the message quoted a foreign charge ("USD 12.99" on a rupee card) whose
  /// converted figure only the bank knows. Null means use the parsed amount.
  int? amountOverride;

  /// When true, this debit is recorded as a contribution to the investments
  /// ledger (a SIP, a stock purchase) instead of as spending. Only offered for
  /// plain expense drafts — see [canBeInvestment].
  bool asInvestment;

  /// The instrument an investment draft is filed under (Stocks, Mutual Funds,
  /// …). Ignored unless [asInvestment] is set.
  String investmentType;

  /// A hand-entered transaction this message appears to duplicate. Set means
  /// the draft starts unselected — importing it would record the same spend
  /// twice.
  Expense? duplicateOf;

  /// Set when [category] came from how this merchant was filed before, rather
  /// than from the default. Shown on the card so a wrong recall is obvious.
  final String? recalledCategory;

  /// Set when [category] is a guess from the merchant's name (see
  /// [MerchantCategories]) because it has never been filed before.
  final String? guessedCategory;

  /// How many accounts share the last four digits the message named. Above
  /// one, no account was picked, and the card says why.
  final int sameLast4Count;

  /// Set when a credit on a credit card was re-read as a payment of its bill
  /// (see [ParsedSms.asCardPayment]).
  final bool isCardPayment;

  /// Set when this merchant+amount has recurred monthly in the history, so the
  /// card can offer to create a recurring rule from it.
  final bool recurringSuggested;

  /// Whether the user accepted that offer — a monthly recurring rule is created
  /// alongside the transaction on import.
  bool createRecurring;

  SmsDraft({
    required this.parsed,
    required this.accountId,
    this.toAccountId,
    required this.category,
    String? description,
    String? paymentMode,
    this.selected = true,
    this.duplicateOf,
    this.recalledCategory,
    this.guessedCategory,
    this.sameLast4Count = 0,
    this.isCardPayment = false,
    this.asInvestment = false,
    this.investmentType = Investment.defaultType,
    this.recurringSuggested = false,
    this.createRecurring = false,
  })  : description = description ?? parsed.description,
        paymentMode = paymentMode ?? parsed.paymentModeFor(null);

  bool get isTransfer => parsed.isTransfer;

  /// A refund, saved as a negative expense against [category].
  bool get isRefund => parsed.isRefund;

  /// Whether the row is filed under spending categories: a debit, or a refund
  /// taking a debit back.
  bool get usesExpenseCategories => parsed.isExpense || parsed.isRefund;

  /// Whether the user may reclassify this draft as an investment. Only a plain
  /// debit qualifies — an incoming credit or a transfer between accounts is not
  /// money being invested.
  bool get canBeInvestment => parsed.isExpense;

  /// A transfer needs both ends to post correctly; without a destination it
  /// would debit the source and credit nothing.
  bool get needsDestination => isTransfer && toAccountId == null;

  /// …and without a source it would credit the destination out of thin air —
  /// the case for a card bill payment, whose message names only the card.
  bool get needsSource => isTransfer && accountId == null;

  /// Whether the parsed amount is in a different currency from [account] (or
  /// the base currency, with no account), so it can't be saved as it stands.
  bool isForeignFor(Account? account) =>
      parsed.currency != (account?.symbol ?? CurrencyFormat.symbol);

  /// Whether this draft still needs its amount entered in [account]'s currency
  /// before it can be imported.
  bool needsAmountFor(Account? account) =>
      isForeignFor(account) && amountOverride == null;

  /// The amount to save, in the account's currency.
  int get amount => amountOverride ?? parsed.amount;

  /// Builds a draft with both accounts pre-resolved from the message, the
  /// category recalled from how this merchant was filed before (or guessed
  /// from its name), and a flag when [existing] already contains a matching
  /// hand-entered row. [claimed] collects the rows already matched to other
  /// drafts in the same scan, so one row isn't the duplicate of several.
  factory SmsDraft.from(
    ParsedSms parsed,
    List<Account> accounts, {
    List<Expense> existing = const [],
    CategoryMemory memory = const CategoryMemory.empty(),
    bool recurringSuggested = false,
    Set<Object>? claimed,
  }) {
    // Money arriving on a credit card that is neither a refund nor cashback
    // is the bill being paid. As income it would count the card bill as
    // earnings; as a transfer it clears what the card owes.
    final landedOn = parsed.matchAccount(accounts);
    final cardPayment =
        parsed.couldBeCardPayment && landedOn?.type == 'credit_card';
    if (cardPayment) parsed = parsed.asCardPayment();

    final account = parsed.matchAccount(accounts);
    final accountId = account?.id;
    final duplicate =
        SmsImport.findDuplicate(parsed, accountId, existing, claimed: claimed);
    final remembered =
        parsed.isTransfer ? null : memory.categoryFor(parsed.description);
    final spending = parsed.isExpense || parsed.isRefund;
    final guessed = parsed.isTransfer || remembered != null || !spending
        ? null
        : MerchantCategories.guess(parsed.description);
    final draft = SmsDraft(
      parsed: parsed,
      accountId: accountId,
      toAccountId: parsed.matchToAccount(accounts)?.id,
      category: parsed.isTransfer
          ? 'Transfer'
          : (remembered ?? guessed ?? (spending ? 'Other' : 'Income')),
      paymentMode: parsed.paymentModeFor(account),
      recalledCategory: remembered,
      guessedCategory: guessed,
      sameLast4Count: parsed.accountsWithLast4(accounts),
      isCardPayment: cardPayment,
      selected: duplicate == null,
      duplicateOf: duplicate,
      recurringSuggested: recurringSuggested,
    );
    // A foreign charge can't be saved until its amount is entered in the
    // account's currency, so it starts unticked rather than blocking Import.
    if (draft.needsAmountFor(account)) draft.selected = false;
    return draft;
  }

  Expense toExpense() => parsed.toExpense(
        accountId: accountId,
        category: category,
        toAccountId: toAccountId,
        description: description,
        amount: amount,
        paymentMode: paymentMode,
      );

  /// The draft as a contribution ready to insert into the investments ledger.
  /// The (possibly edited) description names the holding, the parsed amount and
  /// date carry over, and [investmentType] picks the instrument.
  Investment toInvestment() => Investment(
        name: description,
        amount: amount,
        date: parsed.date,
        type: investmentType,
        // The account the SMS debited: the purchase leaves that balance.
        accountId: accountId,
      );
}
