import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/services/investment_merchants.dart';
import 'package:finance_tracker/services/sms_import.dart';
import 'package:finance_tracker/services/sms_service.dart';

/// Debits that are money being invested arrive on the SMS review screen
/// already set to Investment: from a remembered merchant, or a known
/// investment platform's name.
void main() {
  final received = DateTime(2026, 9, 5, 10);
  ParsedSms parse(String body) =>
      SmsImport.parse(sender: 'VM-HDFCBK', body: body, receivedAt: received)!;

  final bank =
      Account(id: 1, name: 'HDFC Savings', type: 'bank', last4: '4821');
  final other = Account(id: 2, name: 'ICICI', type: 'bank', last4: '9999');

  group('InvestmentMerchants.guessType', () {
    test('recognises platforms and keywords', () {
      expect(InvestmentMerchants.guessType('ZERODHA BROKING'), 'Stocks');
      expect(InvestmentMerchants.guessType('Coin by Zerodha'), 'Mutual Funds');
      expect(InvestmentMerchants.guessType('GROWW'), 'Mutual Funds');
      expect(InvestmentMerchants.guessType('HDFC MF SIP'), 'Mutual Funds');
      expect(InvestmentMerchants.guessType('NPS Trust'), 'NPS');
      expect(InvestmentMerchants.guessType('SafeGold'), 'Gold');
    });

    test('leaves ordinary merchants alone', () {
      for (final m in [
        'SWIGGY', 'Dhan Laxmi Stores', 'AMC renewal', 'ICICI Pru Life', //
        'Mfg Traders', 'Sipla Pharmacy', '',
      ]) {
        expect(InvestmentMerchants.guessType(m), isNull, reason: m);
      }
    });
  });

  group('SmsDraft investment suggestions', () {
    test('a known platform arrives as an investment of the guessed type', () {
      final d = SmsDraft.from(
          parse('Rs.5,000 debited from A/c XX4821 to ZERODHA'), [bank]);
      expect(d.asInvestment, isTrue);
      expect(d.investmentType, 'Stocks');
      expect(d.investmentSuggestion, InvestmentSuggestion.guessed);
      // Paid from the account the message named.
      expect(d.toInvestment().accountId, 1);
    });

    test('a remembered merchant takes its type and holding name', () {
      final p = parse('Rs.2,000 debited from A/c XX4821 to ACME CAPITAL');
      final d = SmsDraft.from(p, [
        bank
      ], investmentMemory: {
        'ACME CAPITAL':
            const InvestmentHint(type: 'Mutual Funds', name: 'Nifty 50'),
      });
      expect(d.asInvestment, isTrue);
      expect(d.investmentType, 'Mutual Funds');
      expect(d.description, 'Nifty 50');
      expect(d.investmentSuggestion, InvestmentSuggestion.remembered);
    });

    test('an ordinary spend stays an expense', () {
      final d = SmsDraft.from(
          parse('Rs.499 debited from A/c XX4821 by UPI to SWIGGY'), [bank]);
      expect(d.asInvestment, isFalse);
      expect(d.investmentSuggestion, InvestmentSuggestion.none);
    });

    test('a bank-to-bank move can be switched to an investment', () {
      final p = parse('Rs.10,000 transferred from A/c XX4821 to A/c XX9999');
      final d = SmsDraft.from(p, [bank, other]);
      expect(d.isTransfer, isTrue);
      expect(d.canBeInvestment, isTrue);
      expect(d.asInvestment, isFalse);
      // As an investment it needs no destination account.
      d.toAccountId = null;
      expect(d.needsDestination, isTrue);
      d.asInvestment = true;
      expect(d.needsDestination, isFalse);
    });
  });

  test('choices are remembered, and switching back to Expense forgets them',
      () async {
    SharedPreferences.setMockInitialValues({});
    final p = parse('Rs.2,000 debited from A/c XX4821 to ACME CAPITAL');
    final d = SmsDraft.from(p, [bank])
      ..asInvestment = true
      ..investmentType = 'Mutual Funds'
      ..description = 'Nifty 50';
    await SmsService.rememberInvestmentChoices(
        investments: [d], expenses: const []);
    final memory = await SmsService.investmentMerchants();
    expect(memory['ACME CAPITAL']?.name, 'Nifty 50');

    final next = SmsDraft.from(p, [bank], investmentMemory: memory);
    expect(next.asInvestment, isTrue);

    next.asInvestment = false;
    await SmsService.rememberInvestmentChoices(
        investments: const [], expenses: [next]);
    expect(await SmsService.investmentMerchants(), isEmpty);
  });
}
