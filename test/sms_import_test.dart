import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/services/sms_import.dart';
import 'package:finance_tracker/utils/db_constants.dart';

/// Sample bodies are real-world bank alert shapes. The parser is pattern
/// matching against templates banks change without notice, so these tests are
/// the only place its accuracy is pinned down.
void main() {
  _transferTests();
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

    test('a message naming both sides is a transfer, not a one-sided debit',
        () {
      final r = parse('Rs.5,000 debited from A/c XX4821 and credited to '
          'A/c XX9999 on 01-Aug-25')!;
      expect(r.type, DbConstants.txTransfer);
      expect(r.last4, '4821');
      expect(r.toLast4, '9999');
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

  group('more real-world templates', () {
    test('ATM withdrawal is an expense on the account', () {
      final r = parse('Rs.3,000 withdrawn from A/c XX4821 at ATM on '
          '01-Aug-25. Avl Bal Rs.5,000')!;
      expect(r.type, DbConstants.txExpense);
      expect(r.amount, 300000);
      expect(r.last4, '4821');
    });

    test('a UPI debit with a "UPI:" handle names the payee', () {
      final r = parse('Rs.199 debited from A/c XX4821 UPI:netflix@ybl')!;
      expect(r.type, DbConstants.txExpense);
      expect(r.amount, 19900);
      expect(r.description, 'netflix@ybl');
      expect(r.last4, '4821');
    });

    test('a refund credited back is income', () {
      final r = parse('Rs.750 refunded to A/c XX4821 by AMAZON on 01-Aug-25')!;
      expect(r.type, DbConstants.txIncome);
      expect(r.amount, 75000);
      expect(r.last4, '4821');
    });

    test('a deposit is income', () {
      final r = parse('INR 10,000 deposited to A/c XX4821 on 01-Aug-25')!;
      expect(r.type, DbConstants.txIncome);
      expect(r.amount, 1000000);
      expect(r.last4, '4821');
    });

    test('a "Dear Customer" preamble does not swallow the transaction', () {
      final r = parse('Dear Customer, Rs.1,200 debited from your A/c XX3344 '
          'on 02-Aug-25. -SBI')!;
      expect(r.type, DbConstants.txExpense);
      expect(r.amount, 120000);
      expect(r.last4, '3344');
    });

    test('a SIP debit parses as an expense (user can mark it investment)', () {
      final r = parse('Rs.5,000 debited from A/c XX4821 towards SIP GROWW '
          'on 01-Aug-25')!;
      expect(r.type, DbConstants.txExpense);
      expect(r.amount, 500000);
      expect(r.description, 'SIP GROWW');
    });

    test('a deducted charge is an expense', () {
      final r = parse('Rs.590 deducted from A/c XX4821 for ANNUAL FEE')!;
      expect(r.type, DbConstants.txExpense);
      expect(r.amount, 59000);
    });
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

/// Transfers between the user's own accounts. Recording these as spending
/// double-counts: a card's purchases already hit the ledger, so the repayment
/// has to move balances rather than add to the month's expenses.
void _transferTests() {
  final received = DateTime(2025, 8, 1, 14, 30);

  ParsedSms? parse(String body, {String sender = 'VM-HDFCBK'}) =>
      SmsImport.parse(sender: sender, body: body, receivedAt: received);

  group('transfer detection', () {
    test('a card bill paid from a bank is a transfer, not an expense', () {
      final r = parse('Rs.15,000.00 debited from A/c XX4821 on 01-Aug-25 '
          'towards HDFC Credit Card XX5678 payment')!;
      expect(r.type, DbConstants.txTransfer);
      expect(r.isTransfer, isTrue);
      expect(r.last4, '4821');
      expect(r.toLast4, '5678');
      expect(r.amount, 1500000);
    });

    test('an NEFT naming both accounts is a transfer', () {
      final r = parse('Rs.20,000 debited from A/c XX4821 and credited to '
          'A/c XX9012 via NEFT on 01-Aug-25')!;
      expect(r.type, DbConstants.txTransfer);
      expect(r.last4, '4821');
      expect(r.toLast4, '9012');
    });

    test('"transferred from X to Y" is no longer dropped', () {
      final r = parse('Rs.5,000 transferred from A/c XX4821 to A/c XX9012')!;
      expect(r.type, DbConstants.txTransfer);
      expect(r.last4, '4821');
      expect(r.toLast4, '9012');
    });

    test('a payment arriving on a card is a credit, not another purchase', () {
      final r = parse('Payment of Rs.15,000 received on your HDFC Bank '
          'Credit Card XX5678. Thank you.')!;
      expect(r.type, DbConstants.txIncome);
      // Lands on the card, so it reduces what is owed.
      expect(r.last4, '5678');
      expect(r.toLast4, isNull);
    });

    test('an ordinary purchase is still a plain expense', () {
      final r = parse('Rs.499 debited from A/c XX4821 on 01-Aug-25 to SWIGGY')!;
      expect(r.type, DbConstants.txExpense);
      expect(r.toLast4, isNull);
      expect(r.description, 'SWIGGY');
    });

    test('a card spend is still a plain expense', () {
      final r = parse('Rs.2,150 spent on Credit Card XX5678 at AMAZON')!;
      expect(r.type, DbConstants.txExpense);
      expect(r.last4, '5678');
      expect(r.toLast4, isNull);
    });

    test('salary credited to one account is income, not a transfer', () {
      final r = parse('INR 45,000 credited to A/c XX4821. Info: SALARY')!;
      expect(r.type, DbConstants.txIncome);
      expect(r.last4, '4821');
      expect(r.toLast4, isNull);
    });

    test('a reference number is not mistaken for an account', () {
      final r = parse('Rs.500 debited from A/c XX4821 to VPA x@ybl '
          'ref 123456789')!;
      expect(r.type, DbConstants.txExpense);
      expect(r.toLast4, isNull);
    });

    test('a transfer resolves both ends against the account list', () {
      final accounts = [
        Account(id: 1, name: 'HDFC Bank', type: 'bank', last4: '4821'),
        Account(id: 2, name: 'HDFC Card', type: 'credit_card', last4: '5678'),
      ];
      final r = parse('Rs.15,000 debited from A/c XX4821 towards '
          'Credit Card XX5678 payment')!;
      expect(r.matchAccount(accounts)!.id, 1);
      expect(r.matchToAccount(accounts)!.id, 2);

      final e = r.toExpense(accountId: 1, category: 'Transfer', toAccountId: 2);
      expect(e.type, DbConstants.txTransfer);
      expect(e.accountId, 1);
      expect(e.toAccountId, 2);
    });

    test('toAccountId is dropped on a non-transfer', () {
      final e = parse('Rs.499 debited from A/c XX4821 to SWIGGY')!
          .toExpense(accountId: 1, category: 'Food', toAccountId: 9);
      expect(e.toAccountId, isNull);
    });
  });

  group('collapsing the two alerts one movement sends', () {
    ParsedSms at(String body, {int hour = 12, String sender = 'VM-HDFCBK'}) =>
        SmsImport.parse(
            sender: sender,
            body: body,
            receivedAt: DateTime(2025, 8, 1, hour))!;

    test('a two-sided transfer absorbs the card-side alert', () {
      final bank = at('Rs.15,000 debited from A/c XX4821 towards '
          'Credit Card XX5678 payment');
      final card = at(
          'Payment of Rs.15,000 received on your Credit Card XX5678',
          hour: 13,
          sender: 'VM-HDFCBK2');

      final out = SmsImport.collapseTransferPairs([bank, card]);
      expect(out.length, 1);
      expect(out.single.type, DbConstants.txTransfer);
      expect(out.single.last4, '4821');
      expect(out.single.toLast4, '5678');
      // The absorbed message is marked seen, so a rescan will not re-offer it.
      expect(out.single.alsoCoversRefs, contains(card.sourceRef));
    });

    test('order does not matter', () {
      final bank = at('Rs.15,000 debited from A/c XX4821 towards '
          'Credit Card XX5678 payment');
      final card = at(
          'Payment of Rs.15,000 received on your Credit Card XX5678',
          hour: 13,
          sender: 'VM-HDFCBK2');
      expect(SmsImport.collapseTransferPairs([card, bank]).length, 1);
    });

    test('a lone debit and a lone credit become one transfer', () {
      final out = SmsImport.collapseTransferPairs([
        at('Rs.20,000 debited from A/c XX4821 to BENEFICIARY'),
        at('INR 20,000 credited to A/c XX9012', hour: 13, sender: 'VM-ICICIB'),
      ]);
      expect(out.length, 1);
      expect(out.single.type, DbConstants.txTransfer);
      expect(out.single.last4, '4821');
      expect(out.single.toLast4, '9012');
      expect(out.single.description, 'Transfer');
    });

    test('different amounts are left alone', () {
      final out = SmsImport.collapseTransferPairs([
        at('Rs.15,000 debited from A/c XX4821 to BENEFICIARY'),
        at('INR 12,000 credited to A/c XX9012', hour: 13),
      ]);
      expect(out.length, 2);
    });

    test('the same amount far apart in time is left alone', () {
      final a = SmsImport.parse(
          sender: 'VM-HDFCBK',
          body: 'Rs.15,000 debited from A/c XX4821 to BENEFICIARY',
          receivedAt: DateTime(2025, 8, 1))!;
      final b = SmsImport.parse(
          sender: 'VM-ICICIB',
          body: 'INR 15,000 credited to A/c XX9012',
          receivedAt: DateTime(2025, 8, 20))!;
      expect(SmsImport.collapseTransferPairs([a, b]).length, 2);
    });

    test('two unrelated expenses of the same amount both survive', () {
      final out = SmsImport.collapseTransferPairs([
        at('Rs.500 debited from A/c XX4821 to SWIGGY'),
        at('Rs.500 debited from A/c XX4821 to ZOMATO', hour: 18),
      ]);
      expect(out.length, 2);
    });

    test('a credit on the same account is not merged into a self-transfer', () {
      final out = SmsImport.collapseTransferPairs([
        at('Rs.500 debited from A/c XX4821 to SWIGGY'),
        at('INR 500 credited to A/c XX4821', hour: 18),
      ]);
      expect(out.length, 2);
    });

    test('an empty list and a single item are unchanged', () {
      expect(SmsImport.collapseTransferPairs([]), isEmpty);
      final one = [at('Rs.500 debited from A/c XX4821 to SWIGGY')];
      expect(SmsImport.collapseTransferPairs(one).length, 1);
    });
  });

  group('duplicates of hand-entered rows', () {
    Expense typed({
      int amount = 49900,
      String? sourceRef,
      int? accountId = 1,
      DateTime? date,
      String type = DbConstants.txExpense,
    }) =>
        Expense(
          description: 'Lunch',
          amount: amount,
          date: date ?? DateTime(2025, 8, 1),
          category: 'Food',
          paymentMode: 'Cash',
          type: type,
          accountId: accountId,
          sourceRef: sourceRef,
        );

    final parsed = parse('Rs.499 debited from A/c XX4821 to SWIGGY')!;

    test('flags a same-amount row on the same account and day', () {
      expect(SmsImport.findDuplicate(parsed, 1, [typed()]), isNotNull);
    });

    test('flags one a day either side', () {
      expect(
          SmsImport.findDuplicate(
              parsed, 1, [typed(date: DateTime(2025, 7, 31))]),
          isNotNull);
    });

    test('ignores one outside the window', () {
      expect(
          SmsImport.findDuplicate(
              parsed, 1, [typed(date: DateTime(2025, 7, 20))]),
          isNull);
    });

    test('ignores a different amount', () {
      expect(SmsImport.findDuplicate(parsed, 1, [typed(amount: 10000)]), isNull);
    });

    test('ignores a different account', () {
      expect(SmsImport.findDuplicate(parsed, 1, [typed(accountId: 2)]), isNull);
    });

    test('still matches when either side has no account', () {
      expect(
          SmsImport.findDuplicate(parsed, null, [typed(accountId: 2)]), isNotNull);
      expect(
          SmsImport.findDuplicate(parsed, 1, [typed(accountId: null)]), isNotNull);
    });

    test('ignores a different direction', () {
      expect(
          SmsImport.findDuplicate(
              parsed, 1, [typed(type: DbConstants.txIncome)]),
          isNull);
    });

    test('never flags a previously imported row', () {
      // Those are already handled by the sourceRef check; matching them would
      // flag a genuine second purchase of the same amount.
      expect(
          SmsImport.findDuplicate(parsed, 1, [typed(sourceRef: 'sms:x:1:a')]),
          isNull);
    });

    test('no history means no duplicate', () {
      expect(SmsImport.findDuplicate(parsed, 1, const []), isNull);
    });
  });
}
