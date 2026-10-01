import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/services/merchant_categories.dart';
import 'package:finance_tracker/services/sms_import.dart';
import 'package:finance_tracker/services/sms_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';

/// The review-queue improvements that need no database: currency and payment
/// mode read from the message, refunds, card bill payments, duplicate
/// ranking, category guesses and shared last-4 digits.
void main() {
  final received = DateTime(2025, 8, 1, 14, 30);

  ParsedSms parse(String body) =>
      SmsImport.parse(sender: 'VM-HDFCBK', body: body, receivedAt: received)!;

  final bank =
      Account(id: 1, name: 'HDFC Savings', type: 'bank', last4: '4821');
  final card =
      Account(id: 2, name: 'HDFC Card', type: 'credit_card', last4: '5678');

  group('currency', () {
    test('a rupee alert is in rupees', () {
      final r = parse('Rs.499 debited from A/c XX4821 to SWIGGY');
      expect(r.currency, SmsImport.rupee);
      expect(r.amount, 49900);
    });

    test('a foreign charge keeps its currency and figure', () {
      final r = parse('USD 12.99 spent on Credit Card XX5678 at NETFLIX');
      expect(r.currency, r'$');
      expect(r.amount, 1299);
      final euro = parse('Txn of €20.00 on card XX5678 at BOOKING');
      expect(euro.currency, '€');
      expect(euro.amount, 2000);
    });

    test('a code no account uses is kept by name', () {
      expect(
          parse('AED 50 spent on card XX5678 at DUBAI MALL').currency, 'AED');
    });

    test('a foreign draft starts unticked until its amount is entered', () {
      final d = SmsDraft.from(
          parse('USD 12.99 spent on Credit Card XX5678 at NETFLIX'), [card]);
      expect(d.needsAmountFor(card), isTrue);
      expect(d.selected, isFalse);

      d.amountOverride = 108900;
      expect(d.needsAmountFor(card), isFalse);
      expect(d.toExpense().amount, 108900);
    });

    test('a charge in the account\'s own currency needs nothing', () {
      final usdCard = Account(
          id: 3,
          name: 'USD Card',
          type: 'credit_card',
          last4: '5678',
          currency: r'$',
          rate: 83);
      final d = SmsDraft.from(
          parse('USD 12.99 spent on Credit Card XX5678 at NETFLIX'), [usdCard]);
      expect(d.needsAmountFor(usdCard), isFalse);
      expect(d.selected, isTrue);
      expect(d.toExpense().amount, 1299);
    });
  });

  group('payment mode', () {
    test('read from the message', () {
      expect(
          parse('Rs.72 debited from A/c XX4821 by UPI to swiggy@icici')
              .paymentMode,
          'UPI');
      expect(
          parse('Txn Rs.72.00 On HDFC Bank Card 5678 At q233@ybl by UPI')
              .paymentMode,
          'UPI');
      expect(
          parse('Rs.2,150 spent on Credit Card XX5678 at AMAZON').paymentMode,
          'Credit Card');
      expect(parse('Rs.800 spent on Debit Card XX4821 at DMART').paymentMode,
          'Debit Card');
      expect(parse('Rs.2000 withdrawn at ATM from A/c XX4821').paymentMode,
          'Cash');
      expect(parse('Rs.499 debited from A/c XX4821 to SWIGGY').paymentMode,
          isNull);
    });

    test('falls back to the account type, then Other', () {
      final r = parse('Rs.499 debited from A/c XX5678 to SWIGGY');
      expect(r.paymentModeFor(card), 'Credit Card');
      expect(r.paymentModeFor(bank), 'Other');
    });

    test('a draft saves the mode it resolved', () {
      final d = SmsDraft.from(
          parse('Rs.499 debited from A/c XX5678 to SWIGGY'), [bank, card]);
      expect(d.paymentMode, 'Credit Card');
      expect(d.toExpense().paymentMode, 'Credit Card');
    });

    test('income carries none, as before', () {
      final d = SmsDraft.from(
          parse('INR 45,000 credited to A/c XX4821. Info: SALARY'), [bank]);
      expect(d.toExpense().paymentMode, '');
    });
  });

  group('refunds', () {
    const body = 'Refund of Rs.500.00 credited to your Card XX5678 from '
        'AMAZON on 01-Aug-25';

    test('are recognised and saved as a negative expense', () {
      final r = parse(body);
      expect(r.isRefund, isTrue);
      final e = r.toExpense(accountId: 2, category: 'Shopping');
      expect(e.type, DbConstants.txExpense);
      expect(e.amount, -50000);
      expect(e.isRefund, isTrue);
    });

    test('use spending categories and are not a card bill payment', () {
      final d = SmsDraft.from(parse(body), [card]);
      expect(d.isRefund, isTrue);
      expect(d.isCardPayment, isFalse);
      expect(d.usesExpenseCategories, isTrue);
      expect(d.category, 'Shopping');
      expect(d.accountId, 2);
    });

    test('are never paired with a same-amount debit as a transfer', () {
      final debit = parse('Rs.500 debited from A/c XX4821 to FLIPKART');
      final refund = parse(body);
      final collapsed = SmsImport.collapseTransferPairs([debit, refund]);
      expect(collapsed.length, 2);
      expect(collapsed.any((p) => p.isTransfer), isFalse);
    });

    test('an ordinary credit is not a refund', () {
      expect(parse('INR 45,000 credited to A/c XX4821. Info: SALARY').isRefund,
          isFalse);
    });
  });

  group('credit card bill payments', () {
    const payment = 'Payment of Rs.15,000 received on your Card XX5678. Thank '
        'you.';

    test('a credit on a card becomes a transfer into it', () {
      final d = SmsDraft.from(parse(payment), [bank, card]);
      expect(d.isCardPayment, isTrue);
      expect(d.isTransfer, isTrue);
      expect(d.toAccountId, 2);
      expect(d.accountId, isNull);
      expect(d.category, 'Transfer');
      // The paying account isn't in the message, so it must be picked.
      expect(d.needsSource, isTrue);

      d.accountId = 1;
      final e = d.toExpense();
      expect(e.type, DbConstants.txTransfer);
      expect(e.accountId, 1);
      expect(e.toAccountId, 2);
      expect(e.amount, 1500000);
    });

    test('a credit on a bank account stays income', () {
      final d = SmsDraft.from(
          parse('INR 45,000 credited to A/c XX4821. Info: SALARY'), [bank]);
      expect(d.isCardPayment, isFalse);
      expect(d.parsed.type, DbConstants.txIncome);
      expect(d.needsSource, isFalse);
    });

    test('cashback on a card stays income', () {
      final d = SmsDraft.from(
          parse('Cashback of Rs.150 credited to your Card XX5678'), [card]);
      expect(d.isCardPayment, isFalse);
      expect(d.parsed.type, DbConstants.txIncome);
    });
  });

  group('accounts sharing last-4 digits', () {
    test('are counted so the card can say why none was picked', () {
      final other = Account(
          id: 3, name: 'ICICI Card', type: 'credit_card', last4: '5678');
      final d = SmsDraft.from(
          parse('Rs.2,150 spent on Credit Card XX5678 at AMAZON'),
          [card, other]);
      expect(d.accountId, isNull);
      expect(d.sameLast4Count, 2);
    });
  });

  group('duplicates', () {
    Expense typed(String description, {DateTime? date, int? id}) => Expense(
          id: id,
          description: description,
          amount: 10000,
          date: date ?? DateTime(2025, 8, 1),
          category: 'Food',
          paymentMode: 'Cash',
        );

    test('one hand-entered row is the duplicate of only one alert', () {
      final first = parse('Rs.100 debited from A/c XX4821 to CHAI POINT');
      final second = parse('Rs.100 debited from A/c XX4821 to METRO CARD');
      final existing = [typed('Tea', id: 7)];
      final claimed = <Object>{};

      expect(SmsImport.findDuplicate(first, 1, existing, claimed: claimed),
          isNotNull);
      expect(SmsImport.findDuplicate(second, 1, existing, claimed: claimed),
          isNull);
    });

    test('prefers the row naming the same merchant', () {
      final p = parse('Rs.100 debited from A/c XX4821 to SWIGGY 88213');
      final match = SmsImport.findDuplicate(p, 1, [
        typed('Lunch', id: 1),
        typed('Swiggy', id: 2, date: DateTime(2025, 7, 31)),
      ]);
      expect(match?.id, 2);
    });

    test('otherwise the closest in date', () {
      final p = parse('Rs.100 debited from A/c XX4821 to SWIGGY');
      final match = SmsImport.findDuplicate(p, 1, [
        typed('Lunch', id: 1, date: DateTime(2025, 7, 30)),
        typed('Snacks', id: 2, date: DateTime(2025, 8, 1)),
      ]);
      expect(match?.id, 2);
    });

    test('a refund matches a hand-entered refund, not a purchase', () {
      final refund = parse('Refund of Rs.100 credited to A/c XX4821 from '
          'SWIGGY');
      expect(SmsImport.findDuplicate(refund, 1, [typed('Swiggy')]), isNull);
      final handRefund = Expense(
          description: 'Swiggy refund',
          amount: -10000,
          date: DateTime(2025, 8, 1),
          category: 'Food',
          paymentMode: 'Other');
      expect(SmsImport.findDuplicate(refund, 1, [handRefund]), isNotNull);
    });

    test('merchant names match through bank noise', () {
      expect(SmsImport.sameMerchantName('SWIGGY 88213', 'Swiggy'), isTrue);
      expect(SmsImport.sameMerchantName('AMAZON PAY', 'Amazon'), isTrue);
      expect(SmsImport.sameMerchantName('Lunch', 'SWIGGY'), isFalse);
      expect(SmsImport.sameMerchantName('A', 'A'), isFalse);
    });
  });

  group('category guesses', () {
    test('recognise well-known merchants', () {
      expect(MerchantCategories.guess('SWIGGY'), 'Food');
      expect(MerchantCategories.guess('swiggy@icici'), 'Food');
      expect(MerchantCategories.guess('UBER INDIA'), 'Transport');
      expect(MerchantCategories.guess('AMAZON PAY'), 'Shopping');
      expect(MerchantCategories.guess('AIRTEL PREPAID'), 'Bills');
      expect(MerchantCategories.guess('NETFLIX'), 'Entertainment');
      expect(MerchantCategories.guess('APOLLO PHARMACY'), 'Health');
      expect(MerchantCategories.guess('UDEMY'), 'Education');
    });

    test('match whole words only', () {
      // "ola" is inside "cola", "jio" inside "jiothing" — neither is the brand.
      expect(MerchantCategories.guess('COCA COLA DEPOT'), isNull);
      expect(MerchantCategories.guess('RAMESH KUMAR'), isNull);
      expect(MerchantCategories.guess(''), isNull);
    });

    test('a remembered category wins over a guess', () {
      // Covered through SmsDraft: with no memory the guess is used.
      final d = SmsDraft.from(
          parse('Rs.499 debited from A/c XX4821 to ZOMATO'), [bank]);
      expect(d.category, 'Food');
      expect(d.guessedCategory, 'Food');
      expect(d.recalledCategory, isNull);
    });

    test('income is never guessed', () {
      final d = SmsDraft.from(
          parse('INR 500 credited to A/c XX4821 from SWIGGY'), [bank]);
      expect(d.guessedCategory, isNull);
      expect(d.category, 'Income');
    });
  });

  group('scan start since the last review', () {
    final now = DateTime(2025, 8, 20, 12);

    test('with no review yet, the default two days', () {
      expect(SmsService.scanStartSince(null, now),
          now.subtract(SmsService.defaultWindow));
    });

    test('a day before an older review', () {
      final reviewed = DateTime(2025, 8, 10, 9);
      expect(SmsService.scanStartSince(reviewed, now),
          reviewed.subtract(const Duration(days: 1)));
    });

    test('never less than two days back', () {
      expect(SmsService.scanStartSince(now, now),
          now.subtract(SmsService.defaultWindow));
    });

    test('never more than the catch-up cap back', () {
      expect(SmsService.scanStartSince(DateTime(2025, 1, 1), now),
          now.subtract(SmsService.maxCatchUp));
    });
  });

  test('refund rows report themselves', () {
    Expense row(int amount, String type) => Expense(
        description: 'x',
        amount: amount,
        date: received,
        category: 'Food',
        paymentMode: 'Other',
        type: type);
    expect(row(-500, DbConstants.txExpense).isRefund, isTrue);
    expect(row(500, DbConstants.txExpense).isRefund, isFalse);
    expect(row(500, DbConstants.txIncome).isRefund, isFalse);
  });
}
