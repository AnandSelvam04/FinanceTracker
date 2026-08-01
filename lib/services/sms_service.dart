import 'dart:io';

import 'package:another_telephony/telephony.dart';

import '../models/account.dart';
import '../models/expense.dart';
import '../services/db_service.dart';
import '../utils/app_logger.dart';
import 'category_memory.dart';
import 'sms_import.dart';

/// Reads the device SMS inbox and hands each message to [SmsImport].
///
/// This is the only file that touches the telephony plugin, so everything that
/// can be unit-tested lives in [SmsImport] instead. Nothing here posts a
/// transaction — [scan] returns candidates for the review queue.
class SmsService {
  SmsService._();

  /// How far back a scan looks.
  ///
  /// Deliberately short: it keeps the first run from dumping months of history
  /// into the queue, and keeps each scan to what has happened since you last
  /// looked. The trade is that a message older than this is never offered, so
  /// going more than a couple of days without opening the screen means those
  /// transactions have to be entered by hand.
  static const defaultWindow = Duration(days: 2);

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
  static Future<List<ParsedSms>> scan({
    Duration window = defaultWindow,
    DateTime? now,
  }) async {
    // Checked here as well as at the permission gate, so no code path can read
    // the inbox while the setting is off.
    if (!isSupported || !enabled) return const [];
    final cutoff = (now ?? DateTime.now()).subtract(window);
    final seen = await DBService().existingSourceRefs();

    final parsed = <ParsedSms>[];
    for (final sms in await _inbox()) {
      if (sms.receivedAt.isBefore(cutoff)) continue;
      final candidate = SmsImport.parse(
        sender: sms.sender,
        body: sms.body,
        receivedAt: sms.receivedAt,
      );
      if (candidate == null || seen.contains(candidate.sourceRef)) continue;
      parsed.add(candidate);
    }
    // Pair up the two alerts one movement produces before sorting, so a card
    // payment shows as a single transfer rather than a debit and a credit.
    final collapsed = SmsImport.collapseTransferPairs(parsed)
      ..sort((a, b) => b.date.compareTo(a.date));
    return collapsed;
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

  /// A hand-entered transaction this message appears to duplicate. Set means
  /// the draft starts unselected — importing it would record the same spend
  /// twice.
  Expense? duplicateOf;

  /// Set when [category] came from how this merchant was filed before, rather
  /// than from the default. Shown on the card so a wrong recall is obvious.
  final String? recalledCategory;

  SmsDraft({
    required this.parsed,
    required this.accountId,
    this.toAccountId,
    required this.category,
    this.selected = true,
    this.duplicateOf,
    this.recalledCategory,
  });

  bool get isTransfer => parsed.isTransfer;

  /// A transfer needs both ends to post correctly; without a destination it
  /// would debit the source and credit nothing.
  bool get needsDestination => isTransfer && toAccountId == null;

  /// Builds a draft with both accounts pre-resolved from the message, the
  /// category recalled from how this merchant was filed before, and a flag
  /// when [existing] already contains a matching hand-entered row.
  factory SmsDraft.from(
    ParsedSms parsed,
    List<Account> accounts, {
    List<Expense> existing = const [],
    CategoryMemory memory = const CategoryMemory.empty(),
  }) {
    final accountId = parsed.matchAccount(accounts)?.id;
    final duplicate = SmsImport.findDuplicate(parsed, accountId, existing);
    final remembered =
        parsed.isTransfer ? null : memory.categoryFor(parsed.description);
    return SmsDraft(
      parsed: parsed,
      accountId: accountId,
      toAccountId: parsed.matchToAccount(accounts)?.id,
      category: parsed.isTransfer
          ? 'Transfer'
          : (remembered ?? (parsed.isExpense ? 'Other' : 'Income')),
      recalledCategory: remembered,
      selected: duplicate == null,
      duplicateOf: duplicate,
    );
  }

  Expense toExpense() => parsed.toExpense(
        accountId: accountId,
        category: category,
        toAccountId: toAccountId,
      );
}
