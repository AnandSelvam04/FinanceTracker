import 'package:flutter_test/flutter_test.dart';

import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/widgets/spend_account_picker.dart';

void main() {
  final bank = Account(id: 1, name: 'Savings', type: 'bank');
  final visa = Account(id: 2, name: 'HDFC Visa', type: 'credit_card');
  final rupay = Account(id: 3, name: 'HDFC RuPay', type: 'credit_card');

  int? pick(String mode, int? current, List<Account> accounts,
          {int? fallback}) =>
      SpendAccountPicker.accountForMode(mode, current, accounts,
          fallbackId: fallback);

  test('choosing Credit Card picks the only card', () {
    expect(pick('Credit Card', 1, [bank, visa]), 2);
  });

  test('with several cards, it waits for one to be picked', () {
    expect(pick('Credit Card', 1, [bank, visa, rupay]), isNull);
    // A card already chosen stays.
    expect(pick('Credit Card', 3, [bank, visa, rupay]), 3);
  });

  test('leaving Credit Card drops the card for the default account', () {
    expect(pick('UPI', 2, [bank, visa], fallback: 1), 1);
    expect(pick('UPI', 2, [bank, visa]), isNull);
    // A non-card account is kept.
    expect(pick('UPI', 1, [bank, visa]), 1);
  });

  test('an account implies its payment mode', () {
    expect(SpendAccountPicker.modeFor('credit_card'), 'Credit Card');
    expect(SpendAccountPicker.modeFor('cash'), 'Cash');
    expect(SpendAccountPicker.modeFor('bank'), isNull);
  });
}
