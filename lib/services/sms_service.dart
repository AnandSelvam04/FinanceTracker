import 'dart:io';

import 'package:another_telephony/telephony.dart';

import '../models/account.dart';
import '../services/db_service.dart';
import '../utils/app_logger.dart';
import 'sms_import.dart';

/// Reads the device SMS inbox and hands each message to [SmsImport].
///
/// This is the only file that touches the telephony plugin, so everything that
/// can be unit-tested lives in [SmsImport] instead. Nothing here posts a
/// transaction — [scan] returns candidates for the review queue.
class SmsService {
  SmsService._();

  /// How far back a scan looks. Bank alerts older than this are almost always
  /// already recorded, and reading the whole inbox on a long-lived phone is
  /// slow enough to feel like a hang.
  static const defaultWindow = Duration(days: 90);

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
    if (!isSupported) return false;
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
    if (!isSupported) return const [];
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
    parsed.sort((a, b) => b.date.compareTo(a.date));
    return parsed;
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
  String category;
  bool selected;

  SmsDraft({
    required this.parsed,
    required this.accountId,
    required this.category,
    this.selected = true,
  });

  /// Builds a draft with the account pre-resolved from the message's last-4.
  factory SmsDraft.from(ParsedSms parsed, List<Account> accounts) {
    return SmsDraft(
      parsed: parsed,
      accountId: parsed.matchAccount(accounts)?.id,
      category: parsed.isExpense ? 'Other' : 'Income',
    );
  }
}
