import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/services/sms_import.dart';
import 'package:finance_tracker/services/sms_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Payee extraction that mistook the amount for a merchant, ICICI's
/// three-digit account masking, and messages from senders that can't be a
/// bank.
void main() {
  final received = DateTime(2025, 10, 28, 14, 30);

  ParsedSms? parse(String body, {String sender = 'VM-ICICIT'}) =>
      SmsImport.parse(sender: sender, body: body, receivedAt: received);

  group('payee', () {
    test("ICICI's '<payee> credited' names the merchant, not the amount", () {
      final r = parse('ICICI Bank Acct XX123 debited for Rs 240.00 on '
          '28-Oct-25; SWIGGY credited. UPI:512345678901. Call 18002662 for '
          'dispute. SMS BLOCK 123 to 9215676766.')!;
      expect(r.type, DbConstants.txExpense);
      expect(r.amount, 24000);
      expect(r.description, 'SWIGGY');
    });

    test('a multi-word payee before credited is kept whole', () {
      final r = parse('ICICI Bank Acct XX123 debited for Rs 1,250.00 on '
          '28-Oct-25; AMAZON PAY INDIA credited.')!;
      expect(r.description, 'AMAZON PAY INDIA');
    });

    test('"for Rs <amount>" is never taken as the merchant', () {
      final r = parse('Acct XX123 debited for Rs.240.00 on 28-Oct-25 at ZOMATO',
          sender: 'VM-HDFCBK')!;
      expect(r.description, 'ZOMATO');
    });

    test('"for INR <amount>" with no payee falls back to the sender', () {
      final r =
          parse('A/c XX4821 debited for INR 500.00', sender: 'VM-HDFCBK')!;
      expect(r.description, 'HDFCBK');
    });

    test('the credited-payee form is not read into a credit', () {
      final r = parse('Dear Customer, Acct XX123 is credited with Rs 5,000.00 '
          'on 28-Oct-25 from JOHN DOE. UPI:512345678901.')!;
      expect(r.type, DbConstants.txIncome);
      expect(r.description, isNot(contains('Rs')));
    });

    test('a merchant whose name merely starts with RS is still a merchant', () {
      final r = parse('Rs.300 debited from A/c XX4821 to RSA MOTORS',
          sender: 'VM-HDFCBK')!;
      expect(r.description, 'RSA MOTORS');
    });
  });

  group('three-digit account masking', () {
    final icici =
        Account(id: 1, name: 'ICICI Savings', type: 'bank', last4: '0123');
    final hdfc =
        Account(id: 2, name: 'HDFC Savings', type: 'bank', last4: '4821');

    test('"Acct XX123" is read as an account reference', () {
      final r = parse('ICICI Bank Acct XX123 debited for Rs 240.00 on '
          '28-Oct-25; SWIGGY credited.')!;
      expect(r.last4, '123');
    });

    test('matches the account whose last four end in those digits', () {
      final r = parse('ICICI Bank Acct XX123 debited for Rs 240.00 on '
          '28-Oct-25; SWIGGY credited.')!;
      expect(r.matchAccount([icici, hdfc])?.id, 1);
      expect(r.accountsWithLast4([icici, hdfc]), 1);
    });

    test('two accounts ending in the digits are ambiguous', () {
      final other = Account(id: 3, name: 'Other', type: 'bank', last4: '9123');
      final r = parse('ICICI Bank Acct XX123 debited for Rs 240.00; '
          'SWIGGY credited.')!;
      expect(r.matchAccount([icici, other]), isNull);
      expect(r.accountsWithLast4([icici, other]), 2);
    });

    test('four digits are still preferred when present', () {
      final r = parse('Rs.499 debited from A/c XXXX4821 to SWIGGY',
          sender: 'VM-HDFCBK')!;
      expect(r.last4, '4821');
    });

    test('a long reference number is still not an account', () {
      final r = parse(
          'Rs.499 debited from A/c XX4821 to SWIGGY. '
          'UPI Ref 123456789012',
          sender: 'VM-HDFCBK')!;
      expect(r.last4, '4821');
      expect(r.toLast4, isNull);
    });

    test('sameAccountRef', () {
      expect(SmsImport.sameAccountRef('123', '0123'), isTrue);
      expect(SmsImport.sameAccountRef('0123', '123'), isTrue);
      expect(SmsImport.sameAccountRef('4821', '4821'), isTrue);
      expect(SmsImport.sameAccountRef('123', '4821'), isFalse);
      expect(SmsImport.sameAccountRef('1234', '0234'), isFalse);
      expect(SmsImport.sameAccountRef(null, '123'), isFalse);
    });

    test('an ICICI debit pairs with the credit naming the full number', () {
      final debit = parse('ICICI Bank Acct XX123 debited for Rs 5,000.00 on '
          '28-Oct-25; IMPS credited.')!;
      final credit = SmsImport.parse(
        sender: 'VM-HDFCBK',
        body: 'Rs.5,000.00 credited to A/c XX4821 on 28-Oct-25',
        receivedAt: received.add(const Duration(minutes: 1)),
      )!;
      final merged = SmsMatching.collapseTransferPairs([debit, credit]);
      expect(merged, hasLength(1));
      expect(merged.single.isTransfer, isTrue);
      expect(merged.single.last4, '123');
      expect(merged.single.toLast4, '4821');
    });
  });

  group('sender', () {
    test('a phone number is not a bank', () {
      expect(SmsImport.isNonBankSender('+919876543210'), isTrue);
      expect(SmsImport.isNonBankSender('9876543210'), isTrue);
      expect(SmsImport.isNonBankSender('+91 98765 43210'), isTrue);
    });

    test('a promotional header is not an alert', () {
      expect(SmsImport.isNonBankSender('VM-HDFCBK-P'), isTrue);
      expect(SmsImport.isNonBankSender('AX-AMAZON-p'), isTrue);
    });

    test('bank headers and short codes are read', () {
      expect(SmsImport.isNonBankSender('VM-HDFCBK'), isFalse);
      expect(SmsImport.isNonBankSender('JD-ICICIT-S'), isFalse);
      expect(SmsImport.isNonBankSender('AD-SBIINB-T'), isFalse);
      expect(SmsImport.isNonBankSender('5676791'), isFalse);
      expect(SmsImport.isNonBankSender('HDFCBK'), isFalse);
    });
  });

  group('scan', () {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DBService.testFactory = databaseFactoryFfi;
    DBService.dbNameOverride = 'sms_capture_fixes_test.db';

    final now = DateTime(2025, 8, 1, 12);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DBService().clearAll();
      SmsService.enabled = true;
    });

    tearDown(() {
      SmsService.inboxOverride = null;
      SmsService.enabled = false;
    });

    test('skips messages from phone numbers and promotional senders', () async {
      RawSms sms(String sender, String body) => RawSms(
          sender: sender,
          body: body,
          receivedAt: now.subtract(const Duration(hours: 2)));
      SmsService.inboxOverride = () async => [
            sms('VM-HDFCBK', 'Rs.499 debited from A/c XX4821 to SWIGGY'),
            sms('+919876543210', 'I sent Rs.500 to MOM, paid from my account'),
            sms('VM-SHOPPR-P', 'Rs.999 debited to SHOPPR on your next order'),
          ];
      final found = await SmsService.scan(now: now);
      expect(found.map((f) => f.description), ['SWIGGY']);
    });
  });
}
