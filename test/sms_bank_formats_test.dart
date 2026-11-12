import 'package:finance_tracker/services/sms_import.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:flutter_test/flutter_test.dart';

/// Alerts in the wording Indian banks actually send, each of which was
/// dropped, booked the wrong way round or given a useless name.
void main() {
  final at = DateTime(2025, 11, 12, 10, 15);
  ParsedSms? parse(String body, {String sender = 'VM-TESTBK'}) =>
      SmsImport.parse(sender: sender, body: body, receivedAt: at);

  group('amounts', () {
    test("SBI's UPI debit quotes the amount with no currency", () {
      final r = parse('Dear UPI user A/C X1234 debited by 500.00 on date '
          '12Nov25 trf to RAMESH KUMAR Refno 531612345678. If not u? call '
          '1800111109. -SBI')!;
      expect(r.type, DbConstants.txExpense);
      expect(r.amount, 50000);
      expect(r.last4, '1234');
      expect(r.description, 'RAMESH KUMAR');
    });

    test('a bare figure without decimals is not taken for an amount', () {
      expect(parse('A/C X1234 debited by 12Nov25 ref 531612345678'), isNull);
    });

    test('"Rs:" with a colon is an amount', () {
      final r = parse('A/c *1234 Debited for Rs:500.00 on 12-11-2025 10:15:30 '
          'by Mob Bk ref no 531612345678 Avl Bal Rs:1234.00.If not you, Call '
          '1800222243 -Union Bank of India')!;
      expect(r.type, DbConstants.txExpense);
      expect(r.amount, 50000);
    });
  });

  group('direction', () {
    test('"debited … and credited to <payee>" is a purchase, not income', () {
      final r = parse('Rs.500.00 debited from A/c XX1234 and credited to '
          'SWIGGY via UPI Ref No 531612345678 on 12Nov25. -Indian Bank')!;
      expect(r.type, DbConstants.txExpense);
      expect(r.description, 'SWIGGY');
      expect(r.last4, '1234');
    });

    test('debited and credited to another account is still a transfer', () {
      final r = parse('Rs.5,000 debited from A/c XX4821 and credited to '
          'A/c XX9012')!;
      expect(r.type, DbConstants.txTransfer);
    });

    test('money credited to your own account stays income', () {
      final r = parse('Refund for the amount debited on 10-Nov: Rs.500 '
          'credited to your A/c XX1234')!;
      expect(r.type, DbConstants.txIncome);
    });

    test("Bank of Baroda's Dr./Cr. are read as the verbs", () {
      final r = parse('Rs.500 Dr. from A/C XXXXXX1234 and Cr. to '
          'merchant@ybl. Ref:531612345678. AvlBal:Rs1234.50(2025:11:12 '
          '10:15:30). Not you? Call 18005700 -BOB')!;
      expect(r.type, DbConstants.txExpense);
      expect(r.amount, 50000);
      expect(r.description, 'merchant@ybl');
    });

    test('the "Cr" of "Avl Cr Lmt" does not make a card spend a credit', () {
      final r = parse('Txn Rs.72.00 On HDFC Bank Card 6955 At shop@ybl by '
          'UPI. Avl Cr Lmt Rs.50,000')!;
      expect(r.type, DbConstants.txExpense);
    });
  });

  group('not transactions', () {
    test('a credit limit increase is not income', () {
      expect(
          parse('Your credit limit on Card XX1234 has been increased to '
              'Rs.2,00,000. Enjoy!'),
          isNull);
    });

    test('an upcoming auto-debit is not a debit yet', () {
      expect(
          parse('Your mandate for NETFLIX of Rs.649.00 will be auto-debited '
              'from A/c XX1234 on 15-Nov-25. -HDFC Bank'),
          isNull);
    });

    test('a failed payment is nothing', () {
      expect(parse('Your UPI txn of Rs.500 to SWIGGY has failed.'), isNull);
    });

    test('money reversed after a failed payment is a refund', () {
      final r = parse('Rs.500.00 reversed to your A/c XX1234 on 12-11-25 for '
          'failed UPI txn 531612345678. -SBI')!;
      expect(r.isRefund, isTrue);
      expect(r.amount, 50000);
    });
  });

  group('accounts', () {
    test('an EMI is paid from the account after "from", not the loan', () {
      final r = parse('Your EMI of Rs.12,345.00 for Loan A/c XX9876 has been '
          'debited from A/c XX1234 on 05-Nov-25. -HDFC Bank')!;
      expect(r.type, DbConstants.txExpense);
      expect(r.last4, '1234');
    });

    test('a card bill paid from a bank account is a transfer to the card', () {
      final r = parse('Card XX5678 bill payment of Rs.5,000 debited from '
          'A/c XX1234')!;
      expect(r.type, DbConstants.txTransfer);
      expect(r.last4, '1234');
      expect(r.toLast4, '5678');
    });

    test('dots as the mask, and the last four of five digits', () {
      expect(
          parse('Rs.2000 Credited to A/c ...1234 thru UPI/531612345678 by '
                  'rahul@okaxis. Total Bal:Rs.3234.5CR')!
              .last4,
          '1234');
      expect(
          parse('Alert: You have spent INR 2,500.00 on your AMEX card ** '
                  '31002 at UBER INDIA on 12 November 2025')!
              .last4,
          '1002');
    });
  });

  group('who it was paid to', () {
    String name(String body) => parse(body)!.description;

    test('the UPI narration names the payee', () {
      expect(
          name('INR 500.00 debited\nA/c no. XX1234\n12-11-25, 10:15:30\n'
              'UPI/P2M/531612345678/BLINKIT\nNot you? SMS BLOCKUPI Cust ID '
              'to 919951860002\nAxis Bank'),
          'BLINKIT');
      expect(
          name('INR 500.00 debited from your A/c XX1234 towards '
              'UPI/531612345678/DR/DMART/YESB. Avl BAL INR 1,234.00'),
          'DMART');
    });

    test('a phone number and the bank signing off are not the payee', () {
      expect(
          name('INR 500.00 debited\nA/c no. XX1234\nNot you? SMS BLOCKUPI '
              'Cust ID to 919951860002\nAxis Bank'),
          'TESTBK');
    });

    test("the line after the time in Axis's card alert", () {
      expect(
          name('Spent\nCard no. XX1234\nINR 500.00\n12-11-25 10:15:30\n'
              'ZOMATO\nAvl Lmt INR 100000.00\nSMS BLOCK 1234 to '
              '919951860002, if not you - Axis Bank'),
          'ZOMATO');
    });

    test('the merchant after the date', () {
      expect(
          name('INR 1,299.00 spent using ICICI Bank Card XX1234 on 12-Nov-25 '
              'on AMAZON PAY IN. Avl Limit: INR 1,85,000.00. If not you, '
              'call 1800 2662/SMS BLOCK 1234 to 9215676766.'),
          'AMAZON PAY IN');
    });

    test('the rail is skipped for the name after it', () {
      expect(
          name('Rs.5000.00 debited from A/c XX1234 on 12-11-25 towards '
              'NACH/ACH mandate for GROWW MF. Avl Bal Rs.1234.00'),
          'GROWW MF');
      expect(
          name('INR 500.00 debited from A/c no. XX1234 on 12NOV25 10:15 at '
              'ECOM/AMAZON. Avl Bal: INR 1,234.00 - YES BANK'),
          'AMAZON');
    });

    test('the Info narration, without its rail', () {
      expect(
          name('UPDATE: INR 5,000.00 debited from HDFC Bank XX1234 on '
              '12-NOV-25. Info: ACH D- ZERODHA BROKING. Avl bal:INR '
              '10,000.00'),
          'ZERODHA BROKING');
    });

    test('who a credit came from', () {
      expect(
          name('Dear Customer, Acct XX123 is credited with Rs 2000.00 on '
              '12-Nov-25 from RAHUL SHARMA. UPI:531612345678-ICICI Bank.'),
          'RAHUL SHARMA');
      expect(
          name('Update! INR 50,000.00 deposited in HDFC Bank A/c XX1234 on '
              '12-NOV-25 for NEFT Cr-SBIN0001234-ACME CORP-JOHN-'
              'SBINN52025111212345.Avl bal INR 60,000.00'),
          'ACME CORP');
      expect(
          name('Rs.2000 Credited to A/c ...1234 thru UPI/531612345678 by '
              'rahul@okaxis. Total Bal:Rs.3234.5CR'),
          'rahul@okaxis');
    });

    test("a credit from the user's own bank account names nobody", () {
      expect(name('Rs.500 received from HDFC Bank A/c XX9012 in A/c XX1234'),
          isNot(contains('Bank')));
    });
  });
}
