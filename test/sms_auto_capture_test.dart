import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_tracker/providers/settings_provider.dart';
import 'package:finance_tracker/services/category_memory.dart';
import 'package:finance_tracker/services/sms_auto_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final at = DateTime(2026, 8, 1, 10);

  SmsCaptureNotice? notice(String body,
          {String sender = 'VM-HDFCBK', Set<String> ignored = const {}}) =>
      SmsAutoCapture.noticeFor(
          sender: sender,
          body: body,
          receivedAt: at,
          ignoredMerchants: ignored);

  test('a card spend is announced with its amount, merchant and card', () {
    final n = notice(
        'Rs.450.00 spent on your HDFC Bank Credit Card XX5678 at SWIGGY on '
        '01-08-26. Avl Lmt: Rs 1,85,000.00')!;
    expect(n.title, startsWith('Spent ₹450.00 · '));
    expect(n.title.toLowerCase(), contains('swiggy'));
    expect(n.body, 'On ••5678. Tap to review and add it.');
    expect(n.id,
        inInclusiveRange(SmsAutoCapture.idBase, SmsAutoCapture.idBase + 99999));
  });

  test('money coming in reads as received', () {
    final n = notice('INR 20,000.00 credited to A/c XX9012 by NEFT from ACME '
        'PAYROLL')!;
    expect(n.title, startsWith('Received ₹20,000.00 · '));
  });

  test('a move between two of your accounts is not called spending', () {
    final n = notice('Rs.15,000 debited from A/c XX4821 and credited to A/c '
        'XX9012 towards fund transfer')!;
    expect(n.title, 'Moved ₹15,000.00 between your accounts');
  });

  test('messages that are not bank transactions raise nothing', () {
    expect(notice('Your OTP for login is 482913. Do not share it.'), isNull);
    expect(notice('Get 50% off on your next order! Use code SAVE50'), isNull);
    // A personal number, even with transaction-like words.
    expect(notice('Rs.500 debited from A/c XX4821', sender: '+919876543210'),
        isNull);
    expect(notice(''), isNull);
  });

  test('a merchant set to Always ignore stays quiet', () {
    const body = 'Rs.199.00 spent on your HDFC Bank Credit Card XX5678 at '
        'NETFLIX on 01-08-26';
    final shown = notice(body)!;
    final merchant = shown.title.split(' · ').last;
    expect(
        notice(body, ignored: {CategoryMemory.merchantKey(merchant)}), isNull);
  });

  test('the same alert always gets the same notification id', () {
    const body = 'Rs.450.00 spent on your HDFC Bank Credit Card XX5678 at '
        'SWIGGY on 01-08-26';
    expect(notice(body)!.id, notice(body)!.id);
    expect(
        notice(body)!.id, isNot(notice(body.replaceFirst('450', '451'))!.id));
  });

  test('the setting is off by default and needs SMS reading on', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.load();
    expect(settings.smsAutoCapture, isFalse);

    await settings.setSmsAutoCapture(true);
    // Still off: SMS reading itself is not switched on.
    expect(settings.smsAutoCapture, isFalse);

    await settings.setSmsImportEnabled(true);
    expect(settings.smsAutoCapture, isTrue);

    final reloaded = SettingsProvider();
    await reloaded.load();
    expect(reloaded.smsAutoCapture, isTrue);

    await settings.setSmsImportEnabled(false);
    expect(settings.smsAutoCapture, isFalse);
  });
}
