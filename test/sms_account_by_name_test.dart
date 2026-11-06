import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/services/sms_import.dart';
import 'package:finance_tracker/services/sms_service.dart';

/// A card alert with no card number is matched by the account's name, and
/// HDFC's "At PTM*FLIPKART M On …" names its merchant.
void main() {
  final received = DateTime(2026, 11, 6, 12, 41);
  ParsedSms parse(String body, {String sender = 'VM-HDFCBK-S'}) =>
      SmsImport.parse(sender: sender, body: body, receivedAt: received)!;

  final hdfc = Account(
      id: 1, name: 'HDFC Credit Card', type: 'credit_card', last4: '9812');
  final hdfcUpi = Account(
      id: 2, name: 'HDFC UPI Credit Card', type: 'credit_card', last4: '6955');
  final scapia = Account(id: 3, name: 'Scapia Federal', type: 'credit_card');
  final accounts = [hdfc, hdfcUpi, scapia];

  const scapiaAlert = 'Your txn of ₹128.00 at Zepto on your Scapia Federal '
      'Visa credit card earned you 10% rewards! Not you? Call 18002961199. '
      '- Federal Bank';
  const hdfcAlert = 'Spent Rs.705 On HDFC Bank Card 9812 At PTM*FLIPKART M On '
      '2026-11-06:12:40:34.Not You? To Block+Reissue Call 18002586161/SMS '
      'BLOCK CC 9812 to 7308080808';

  group('an alert with no card number', () {
    test('goes to the account its name mentions', () {
      final p = parse(scapiaAlert, sender: 'JD-FEDSCP-S');
      expect(p.last4, isNull);
      expect(p.description, 'Zepto');
      final d = SmsDraft.from(p, accounts);
      expect(d.accountId, 3);
      expect(d.paymentMode, 'Credit Card');
    });

    test('generic words like "credit card" or "bank" do not match', () {
      final p = parse('Rs.500 spent on your credit card at AMAZON. - Bank');
      expect(
          p.matchAccount(
              [Account(id: 9, name: 'My Credit Card', type: 'credit_card')]),
          isNull);
    });

    test('two accounts matching equally well are left to the user', () {
      final p = parse('Rs.500 spent on your HDFC credit card at AMAZON');
      // Both HDFC cards share "HDFC"; neither number is in the message.
      expect(p.matchAccount([hdfc, hdfcUpi]), isNull);
    });

    test('the closer name wins', () {
      final federalSavings =
          Account(id: 4, name: 'Federal Savings', type: 'bank');
      final p = parse(scapiaAlert, sender: 'JD-FEDSCP-S');
      // "Federal" is in both, "Scapia" only in the card.
      expect(p.matchAccount([federalSavings, scapia])?.id, 3);
    });

    test('a credit-card alert prefers a credit-card account', () {
      final federalSavings =
          Account(id: 4, name: 'Federal Savings', type: 'bank');
      final federalCard =
          Account(id: 5, name: 'Federal Card', type: 'credit_card');
      final p = parse('Your txn of ₹99.00 at Zepto on your Federal credit card '
          'was successful');
      expect(p.matchAccount([federalSavings, federalCard])?.id, 5);
    });

    test('a number in the message still decides, never the name', () {
      final p = parse('Rs.500 spent on Scapia Card XX1111 at AMAZON');
      expect(p.last4, '1111');
      expect(p.matchAccount(accounts), isNull);
    });
  });

  group('HDFC "Spent … At PTM*FLIPKART M On …"', () {
    test('goes to the card the number names', () {
      final p = parse(hdfcAlert);
      expect(p.last4, '9812');
      expect(p.amount, 70500);
      final d = SmsDraft.from(p, accounts);
      expect(d.accountId, 1);
      expect(d.sameLast4Count, 1);
    });

    test('names the merchant, without the gateway tag or the date', () {
      expect(parse(hdfcAlert).description, 'FLIPKART M');
    });

    test('other gateways and capitalised prepositions', () {
      expect(
          parse('Rs.299 spent on Card XX9812 At RAZ*SWIGGY On 06-11-26')
              .description,
          'SWIGGY');
      expect(parse('Rs.150 debited from A/c XX4821 To ZOMATO').description,
          'ZOMATO');
    });

    test('a "To Block" footer is not taken for the payee', () {
      final p = parse('Spent Rs.705 On HDFC Bank Card 9812. Not You? To '
          'Block+Reissue Call 18002586161');
      expect(p.description, isNot(startsWith('Block')));
    });

    test('the other HDFC card gets its own alerts', () {
      final p = parse('Txn Rs.72.00 On HDFC Bank Card 6955 At q233098266@ybl '
          'by UPI 512345678901');
      expect(SmsDraft.from(p, accounts).accountId, 2);
    });
  });
}
