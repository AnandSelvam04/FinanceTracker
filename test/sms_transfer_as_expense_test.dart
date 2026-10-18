import 'package:flutter_test/flutter_test.dart';

import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/services/sms_import.dart';
import 'package:finance_tracker/services/sms_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';

/// Money sent to someone else's account (family, a friend) names two account
/// numbers, so it is read as a transfer — but it is spending, and the review
/// screen can record it as an expense.
void main() {
  final received = DateTime(2026, 9, 5, 10);
  ParsedSms parse(String body) =>
      SmsImport.parse(sender: 'VM-HDFCBK', body: body, receivedAt: received)!;

  final bank =
      Account(id: 1, name: 'HDFC Savings', type: 'bank', last4: '4821');
  final other = Account(id: 2, name: 'ICICI', type: 'bank', last4: '9999');
  const sent = 'Rs.5,000 transferred from A/c XX4821 to A/c XX7777 by IMPS';

  test('sent to an account that is not yours starts as an expense', () {
    final d = SmsDraft.from(parse(sent), [bank, other]);
    expect(d.isTransfer, isTrue);
    expect(d.asExpense, isTrue);
    expect(d.recordsTransfer, isFalse);
    expect(d.usesExpenseCategories, isTrue);
    expect(d.category, 'Other');
    // No receiving account is needed for spending.
    expect(d.needsDestination, isFalse);

    final e = d.toExpense();
    expect(e.type, DbConstants.txExpense);
    expect(e.accountId, bank.id);
    expect(e.toAccountId, isNull);
    expect(e.amount, 500000);
  });

  test('a move between your own accounts stays a transfer', () {
    final d = SmsDraft.from(
        parse('Rs.5,000 transferred from A/c XX4821 to A/c XX9999'),
        [bank, other]);
    expect(d.asExpense, isFalse);
    expect(d.recordsTransfer, isTrue);
    expect(d.category, 'Transfer');
    expect(d.toExpense().type, DbConstants.txTransfer);
  });

  test('switching back to Transfer asks for the receiving account', () {
    final d = SmsDraft.from(parse(sent), [bank, other]);
    d.setAsExpense(false);
    expect(d.category, 'Transfer');
    expect(d.needsDestination, isTrue);
    d.toAccountId = other.id;
    final e = d.toExpense();
    expect(e.type, DbConstants.txTransfer);
    expect(e.toAccountId, other.id);
  });

  test('a card bill payment cannot be recorded as an expense', () {
    final card =
        Account(id: 3, name: 'HDFC Card', type: 'credit_card', last4: '5678');
    final d = SmsDraft.from(
        parse('Rs.15,000 debited from A/c XX4821 towards HDFC Credit Card '
            'XX5678 payment'),
        [bank, card]);
    expect(d.canBeExpense, isFalse);
    expect(d.asExpense, isFalse);
  });
}
