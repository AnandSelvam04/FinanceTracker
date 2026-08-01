import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/services/sms_import.dart';
import 'package:finance_tracker/utils/db_constants.dart';

/// Sample bodies are real-world bank alert shapes. The parser is pattern
/// matching against templates banks change without notice, so these tests are
/// the only place its accuracy is pinned down.
void main() {
  final received = DateTime(2025, 8, 1, 14, 30);

  ParsedSms? parse(String body, {String sender = 'VM-HDFCBK'}) =>
      SmsImport.parse(sender: sender, body: body, receivedAt: received);

  group('direction', () {
    test('debit wording is an expense', () {
      final r = parse('Rs.499.00 debited from A/c XX4821 on 01-Aug-25 to '
          'SWIGGY. Avl Bal Rs.12,340.00')!;
      expect(r.type, DbConstants.txExpense);
      expect(r.isExpense, isTrue);
    });

    test('credit wording is income', () {
      final r = parse('INR 45,000.00 credited to A/c XX4821 on 01-Aug-25. '
          'Info: SALARY AUG. Avl Bal INR 57,340.00')!;
      expect(r.type, DbConstants.txIncome);
    });

    test('"credit card" does not flip a spend to income', () {
      final r = parse('Rs.2,150.00 spent on HDFC Bank Credit Card XX5678 at '
          'AMAZON on 01-Aug-25')!;
      expect(r.type, DbConstants.txExpense);
      expect(r.amount, 215000);
    });

    test('debit card spend stays an expense', () {
      final r = parse('Rs.320 debited via Debit Card XX1234 at STARBUCKS')!;
      expect(r.type, DbConstants.txExpense);
    });

    test('a transfer leg keeps the direction of the earlier verb', () {
      final r = parse('Rs.5,000 debited from A/c XX4821 and credited to '
          'A/c XX9999 on 01-Aug-25')!;
      expect(r.type, DbConstants.txExpense);
    });
  });

  group('amount', () {
    test('takes the transaction amount, not the trailing balance', () {
      final r = parse('Rs.499.00 debited from A/c XX4821 on 01-Aug-25 to '
          'SWIGGY. Avl Bal Rs.12,340.00')!;
      expect(r.amount, 49900);
    });

    test('skips a leading available-balance clause', () {
      final r = parse('Available balance Rs.12,340.00. Rs.750 debited from '
          'A/c XX4821 at BIGBASKET')!;
      expect(r.amount, 75000);
    });

    test('ignores a credit limit figure', () {
      final r = parse('Rs.899 spent on card XX5678 at NETFLIX. '
          'Unbilled amount Rs.4,500. Limit Rs.2,00,000')!;
      expect(r.amount, 89900);
    });

    test('handles thousands separators and the INR prefix', () {
      expect(parse('INR 1,23,456.78 debited from A/c XX1111')!.amount,
          12345678);
    });

    test('handles the rupee symbol with no space', () {
      expect(parse('₹499 debited from A/c XX1111')!.amount, 49900);
    });

    test('returns null when there is no amount at all', () {
      expect(parse('Your A/c XX4821 was debited yesterday'), isNull);
    });
  });

  group('account last-4', () {
    test('reads an A/c number', () {
      expect(parse('Rs.499 debited from A/c XX4821 to SWIGGY')!.last4, '4821');
    });

    test('reads a card ending', () {
      expect(
          parse('Rs.2,150 spent on Credit Card ending 5678 at AMAZON')!.last4,
          '5678');
    });

    test('reads a long masked number', () {
      expect(parse('Rs.100 debited from account XXXXXX9012')!.last4, '9012');
    });

    test('is null when the message names no account', () {
      expect(parse('Rs.100 debited towards AUTOPAY')!.last4, isNull);
    });
  });

  group('merchant', () {
    test('picks an upper-case merchant after "to"', () {
      expect(parse('Rs.499 debited from A/c XX4821 on 01-Aug-25 to SWIGGY. '
              'Avl Bal Rs.12,340')!
          .description, 'SWIGGY');
    });

    test('picks a multi-word merchant after "at"', () {
      expect(
          parse('Rs.2,150 spent on card XX5678 at AMAZON PAY INDIA')!
              .description,
          'AMAZON PAY INDIA');
    });

    test('picks a UPI handle', () {
      expect(
          parse('Rs.250 debited from A/c XX4821 to VPA merchant@ybl')!
              .description,
          'merchant@ybl');
    });

    test('falls back to the cleaned sender id', () {
      expect(parse('Rs.100 debited from A/c XX4821', sender: 'VM-HDFCBK')!
          .description, 'HDFCBK');
    });
  });

  group('date', () {
    test('prefers the date inside the message', () {
      expect(parse('Rs.499 debited from A/c XX4821 on 12-Jul-25 to SWIGGY')!
          .date, DateTime(2025, 7, 12));
    });

    test('reads a numeric date', () {
      expect(parse('Rs.499 debited on 03/02/2025 to SWIGGY')!.date,
          DateTime(2025, 2, 3));
    });

    test('falls back to the SMS timestamp', () {
      expect(parse('Rs.499 debited from A/c XX4821 to SWIGGY')!.date, received);
    });

    test('rejects an impossible date and falls back', () {
      expect(parse('Rs.499 debited on 31/02/2025 to SWIGGY')!.date, received);
    });
  });

  group('non-transactions are rejected', () {
    for (final body in [
      '123456 is your OTP for a txn of Rs.5,000 on card XX5678. Do not share.',
      'Rs.2,000 will be debited from A/c XX4821 on 05-Aug-25 towards SIP.',
      'Your statement is ready. Total due Rs.12,340 on A/c XX5678.',
      'Get 10% cashback offer up to Rs.500 at AMAZON. Click here to apply now.',
      'Payment of Rs.999 to NETFLIX has failed. Please retry.',
      'Rs.500 transaction on card XX5678 was declined.',
    ]) {
      test('"${body.substring(0, 32)}..."', () {
        expect(parse(body), isNull);
      });
    }

    test('a message with no direction word is rejected', () {
      expect(parse('Your balance on A/c XX4821 is Rs.12,340'), isNull);
    });

    test('an empty body is rejected', () => expect(parse('   '), isNull));
  });

  group('sourceRef', () {
    test('is stable for the same message', () {
      final a = SmsImport.sourceRefFor('VM-HDFCBK', received, 'Rs.10 debited');
      final b = SmsImport.sourceRefFor('VM-HDFCBK', received, 'Rs.10 debited');
      expect(a, b);
    });

    test('differs when the body differs at the same instant', () {
      final a = SmsImport.sourceRefFor('VM-HDFCBK', received, 'Rs.10 debited');
      final b = SmsImport.sourceRefFor('VM-HDFCBK', received, 'Rs.20 debited');
      expect(a, isNot(b));
    });

    test('differs by sender and by timestamp', () {
      final base = SmsImport.sourceRefFor('VM-HDFCBK', received, 'x');
      expect(base, isNot(SmsImport.sourceRefFor('VM-ICICIB', received, 'x')));
      expect(
          base,
          isNot(SmsImport.sourceRefFor(
              'VM-HDFCBK', received.add(const Duration(seconds: 1)), 'x')));
    });

    test('is case-insensitive on the sender', () {
      expect(SmsImport.sourceRefFor('VM-HDFCBK', received, 'x'),
          SmsImport.sourceRefFor('vm-hdfcbk', received, 'x'));
    });
  });

  group('account matching', () {
    Account acct(int id, String name, String? last4) =>
        Account(id: id, name: name, type: 'bank', last4: last4);

    test('routes to the account whose last-4 matches', () {
      final accounts = [
        acct(1, 'HDFC Savings', '4821'),
        acct(2, 'HDFC Credit Card', '5678'),
      ];
      final spend =
          parse('Rs.2,150 spent on Credit Card XX5678 at AMAZON')!;
      expect(spend.matchAccount(accounts)!.id, 2);

      final debit = parse('Rs.499 debited from A/c XX4821 to SWIGGY')!;
      expect(debit.matchAccount(accounts)!.id, 1);
    });

    test('is null when no account claims the digits', () {
      expect(
          parse('Rs.499 debited from A/c XX0000 to SWIGGY')!
              .matchAccount([acct(1, 'HDFC', '4821')]),
          isNull);
    });

    test('is null when the digits are ambiguous', () {
      final accounts = [acct(1, 'A', '4821'), acct(2, 'B', '4821')];
      expect(
          parse('Rs.499 debited from A/c XX4821')!.matchAccount(accounts),
          isNull);
    });

    test('ignores accounts with no last-4 set', () {
      expect(
          parse('Rs.499 debited from A/c XX4821')!
              .matchAccount([acct(1, 'A', null)]),
          isNull);
    });
  });

  group('toExpense', () {
    test('carries the sourceRef and the resolved account', () {
      final parsed = parse('Rs.499 debited from A/c XX4821 to SWIGGY')!;
      final e = parsed.toExpense(accountId: 7, category: 'Food');
      expect(e.amount, 49900);
      expect(e.accountId, 7);
      expect(e.category, 'Food');
      expect(e.type, DbConstants.txExpense);
      expect(e.sourceRef, parsed.sourceRef);
      // Always positive; direction lives in `type`, matching how the rest of
      // the app stores amounts.
      expect(e.amount.isNegative, isFalse);
    });
  });
}
