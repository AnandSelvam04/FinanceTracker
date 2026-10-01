import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/services/csv_import.dart';
import 'package:finance_tracker/services/sms_import.dart';
import 'package:finance_tracker/services/sms_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';

/// A card bill paid from a bank whose alert doesn't name the card, and
/// refunds arriving through a CSV statement. Both used to inflate totals: the
/// bill as a second round of spending, the refund as income.
void main() {
  final received = DateTime(2025, 8, 1, 14, 30);
  ParsedSms parse(String body) =>
      SmsImport.parse(sender: 'VM-HDFCBK', body: body, receivedAt: received)!;

  final bank =
      Account(id: 1, name: 'HDFC Savings', type: 'bank', last4: '4821');
  final card =
      Account(id: 2, name: 'HDFC Card', type: 'credit_card', last4: '5678');
  final card2 =
      Account(id: 3, name: 'ICICI Card', type: 'credit_card', last4: '9012');

  group('a card bill paid from the bank', () {
    const bodies = [
      'Rs.15,000.00 debited from A/c XX4821 towards Credit Card bill payment',
      'Rs 15000 debited from a/c XX4821 for HDFC Credit Card payment',
      'INR 15,000 debited from A/c XX4821 towards your HDFC Bank Credit Card',
      'Rs.15000 paid from A/c XX4821 to CRED via UPI cred.club@axisb',
      'Rs.15000 debited from A/c XX4821 for CC bill payment. Ref 123456',
    ];

    for (final body in bodies) {
      test('is a transfer, not spending: "$body"', () {
        final p = parse(body);
        expect(p.isCardBillPayment, isTrue);
        final d = SmsDraft.from(p, [bank, card]);
        expect(d.isTransfer, isTrue);
        expect(d.isCardPayment, isTrue);
        expect(d.accountId, 1);
        expect(d.category, 'Transfer');
      });
    }

    test('picks the card when it is the only one', () {
      final d = SmsDraft.from(parse(bodies.first), [bank, card]);
      expect(d.toAccountId, 2);
      expect(d.needsDestination, isFalse);
      final e = d.toExpense();
      expect(e.type, DbConstants.txTransfer);
      expect(e.accountId, 1);
      expect(e.toAccountId, 2);
      expect(e.amount, 1500000);
    });

    test('asks which card when there are several', () {
      final d = SmsDraft.from(parse(bodies.first), [bank, card, card2]);
      expect(d.toAccountId, isNull);
      expect(d.needsDestination, isTrue);
    });

    test('uses the card the message does name', () {
      final d = SmsDraft.from(
          parse('Rs.15,000 debited from A/c XX4821 towards Credit Card '
              'XX9012 bill'),
          [bank, card, card2]);
      expect(d.isTransfer, isTrue);
      expect(d.toAccountId, 3);
    });

    test('a purchase on a card stays a purchase', () {
      for (final body in [
        'Rs.2,150 spent on Credit Card XX5678 at AMAZON',
        'Rs.500 debited from Credit Card XX5678 for purchase at CROMA',
        'Card payment of Rs.500 at AMAZON from A/c XX4821',
        'Rs.499 debited from A/c XX4821 to SWIGGY',
      ]) {
        final d = SmsDraft.from(parse(body), [bank, card]);
        expect(d.isTransfer, isFalse, reason: body);
        expect(d.parsed.isExpense, isTrue, reason: body);
      }
    });

    test('a bill-payment debit on a card account is not re-read', () {
      // The money left a card, so whatever the wording, it isn't the bank
      // paying the card.
      final d = SmsDraft.from(
          parse('Rs.1,000 debited from Card XX5678 towards CC bill'),
          [bank, card]);
      expect(d.isTransfer, isFalse);
    });

    test('"credited" is not mistaken for CRED', () {
      expect(
          parse('Rs.500 debited from A/c XX4821. Credited to SWIGGY')
              .isCardBillPayment,
          isFalse);
    });
  });

  group('CSV refunds', () {
    const mapping = CsvColumnMapping(
        dateCol: 0, descriptionCol: 1, amountCol: 2, categoryCol: 3);

    test('a signed credit naming a refund is a negative expense', () {
      final r = parseCsvExpenses([
        ['2025-08-01', 'AMAZON purchase', '-2000', 'Shopping'],
        ['2025-08-03', 'REFUND AMAZON', '500', 'Shopping'],
        ['2025-08-05', 'SALARY', '45000', 'Salary'],
      ], hasHeader: false, mapping: mapping);

      final refund = r.expenses[1];
      expect(refund.type, DbConstants.txExpense);
      expect(refund.amount, -50000);
      expect(refund.isRefund, isTrue);
      expect(refund.category, 'Shopping');

      // Ordinary rows are unchanged.
      expect(r.expenses[0].amount, 200000);
      expect(r.expenses[0].type, DbConstants.txExpense);
      expect(r.expenses[2].type, DbConstants.txIncome);
      expect(r.expenses[2].amount, 4500000);
    });

    test('a credit from a type column is caught too', () {
      final r = parseCsvExpenses([
        ['2025-08-03', 'Reversal of txn FLIPKART', '799', 'Shopping', 'CR'],
        ['2025-08-04', 'Interest', '120', 'Interest', 'CR'],
      ],
          hasHeader: false,
          mapping: const CsvColumnMapping(
              dateCol: 0,
              descriptionCol: 1,
              amountCol: 2,
              categoryCol: 3,
              typeCol: 4));
      expect(r.expenses[0].isRefund, isTrue);
      expect(r.expenses[0].amount, -79900);
      expect(r.expenses[1].type, DbConstants.txIncome);
    });

    test('a debit naming a refund is left alone', () {
      // Money out is never a refund, whatever the description says.
      final r = parseCsvExpenses([
        ['2025-08-03', 'Refund processing fee', '-50', 'Bills'],
        ['2025-08-04', 'x', '1', 'x'],
      ], hasHeader: false, mapping: mapping);
      expect(r.expenses[0].type, DbConstants.txExpense);
      expect(r.expenses[0].amount, 5000);
    });

    test('re-importing the same statement still skips refunds', () {
      final rows = [
        ['2025-08-01', 'AMAZON', '-2000', 'Shopping'],
        ['2025-08-03', 'REFUND AMAZON', '500', 'Shopping'],
      ];
      final first = parseCsvExpenses(rows, hasHeader: false, mapping: mapping);
      final again = parseCsvExpenses(rows, hasHeader: false, mapping: mapping)
          .withoutAlreadyImported(
              {for (final e in first.expenses) e.sourceRef!});
      expect(again.expenses, isEmpty);
      expect(again.duplicates, 2);
    });

    test('words that only contain "refund" do not count', () {
      expect(isCsvRefund('REFUND AMAZON'), isTrue);
      expect(isCsvRefund('Chargeback credit'), isTrue);
      expect(isCsvRefund('Refundable deposit'), isFalse);
      expect(isCsvRefund('SALARY'), isFalse);
    });
  });
}
