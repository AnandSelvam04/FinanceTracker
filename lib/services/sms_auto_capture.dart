import 'package:another_telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';
import '../utils/currency_format.dart';
import 'category_memory.dart';
import 'notification_service.dart';
import 'sms_import.dart';
import 'sms_service.dart';

/// Runs when a message arrives while the app is closed or in the background.
/// The plugin starts a Dart isolate just for it, so nothing the running app
/// set up (settings, the notification plugin) exists here: [SmsAutoCapture]
/// reads what it needs from preferences each time.
///
/// Top-level and kept by the compiler, as the plugin looks it up by handle.
@pragma('vm:entry-point')
Future<void> smsBackgroundHandler(SmsMessage message) =>
    SmsAutoCapture.onMessage(message);

/// What to tell the user about a bank alert that just arrived.
class SmsCaptureNotice {
  final int id;
  final String title;
  final String body;
  const SmsCaptureNotice(
      {required this.id, required this.title, required this.body});
}

/// Notices a bank transaction alert the moment it arrives and raises a
/// notification for it, so the transaction is one tap from being added
/// instead of waiting for the next manual scan.
///
/// Nothing is recorded here. The notification opens the SMS review queue,
/// where the message is found by the ordinary inbox scan and goes through the
/// same account matching, duplicate check and confirmation as any other. That
/// keeps one path into the ledger, and means the background isolate never
/// opens the (possibly encrypted) database.
class SmsAutoCapture {
  SmsAutoCapture._();

  /// Preference: notify about transactions as their SMS arrives. Only acts
  /// while SMS reading itself is on.
  static const prefsKey = 'smsAutoCapture';
  static const _kSmsImport = 'smsImportEnabled';
  static const _kIgnoredMerchants = 'smsIgnoredMerchants';

  /// Notification ids for captured alerts: a band of its own above the
  /// bill, budget, card and daily-reminder ids.
  static const idBase = 400000;
  static const _idSpan = 100000;

  /// The notification for an incoming message, or null when it is not a
  /// transaction alert worth raising: not from a bank, not a transaction, or
  /// from a merchant the user chose to ignore. Pure, for tests.
  static SmsCaptureNotice? noticeFor({
    required String sender,
    required String body,
    required DateTime receivedAt,
    Set<String> ignoredMerchants = const {},
  }) {
    if (SmsImport.isNonBankSender(sender)) return null;
    final parsed =
        SmsImport.parse(sender: sender, body: body, receivedAt: receivedAt);
    if (parsed == null) return null;
    if (!parsed.isTransfer &&
        ignoredMerchants
            .contains(CategoryMemory.merchantKey(parsed.description))) {
      return null;
    }
    final amount = formatMoneyInExact(parsed.currency, parsed.amount);
    return SmsCaptureNotice(
      id: idFor(parsed.sourceRef),
      title: _title(parsed, amount),
      body: [
        if (parsed.last4 != null) 'On ••${parsed.last4}.',
        'Tap to review and add it.',
      ].join(' '),
    );
  }

  static String _title(ParsedSms p, String amount) {
    if (p.isTransfer) return 'Moved $amount between your accounts';
    if (p.isRefund) return 'Refund of $amount · ${p.description}';
    if (p.isExpense) return 'Spent $amount · ${p.description}';
    return 'Received $amount · ${p.description}';
  }

  /// A stable id inside the capture band for a message, so the same alert
  /// delivered twice replaces its notification instead of adding a second.
  static int idFor(String sourceRef) {
    var hash = 0;
    for (final unit in sourceRef.codeUnits) {
      hash = (hash * 31 + unit) % _idSpan;
    }
    return idBase + hash;
  }

  /// Handles one incoming message, in the app or in the background isolate.
  static Future<void> onMessage(SmsMessage message) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Read afresh: in the background isolate nothing has loaded the
      // settings, and in the app they may have changed since listening began.
      await prefs.reload();
      if (!(prefs.getBool(_kSmsImport) ?? false) ||
          !(prefs.getBool(prefsKey) ?? false)) {
        return;
      }
      final body = message.body;
      if (body == null || body.isEmpty) return;
      final notice = noticeFor(
        sender: message.address ?? '',
        body: body,
        receivedAt: DateTime.fromMillisecondsSinceEpoch(
            message.date ?? DateTime.now().millisecondsSinceEpoch),
        ignoredMerchants:
            (prefs.getStringList(_kIgnoredMerchants) ?? const []).toSet(),
      );
      if (notice == null) return;
      await NotificationService.instance.init();
      await NotificationService.instance.showSmsCapture(notice);
    } catch (e, s) {
      AppLogger.error('Handling an incoming SMS failed', e, s);
    }
  }

  /// Starts (or, with [on] false, stops) listening for incoming messages.
  /// Safe to call on every launch; does nothing where SMS isn't supported.
  static void listen({required bool on}) {
    if (!SmsService.isSupported || SmsService.inboxOverride != null) return;
    try {
      if (on) {
        Telephony.instance.listenIncomingSms(
          onNewMessage: onMessage,
          onBackgroundMessage: smsBackgroundHandler,
        );
      } else {
        // Registering without a background handler switches the plugin's
        // background service off.
        Telephony.instance.listenIncomingSms(
          onNewMessage: (_) {},
          listenInBackground: false,
        );
      }
    } catch (e, s) {
      AppLogger.error('Listening for incoming SMS failed', e, s);
    }
  }
}
