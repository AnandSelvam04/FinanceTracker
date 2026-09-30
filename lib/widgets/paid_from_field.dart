import 'package:flutter/material.dart';

import '../models/account.dart';

/// "Paid from" picker for an investment: which account the money left.
///
/// A bank, UPI or cash account's balance drops by the amount. On a credit
/// card it is added to what's owed, lands on the card's statement, and the
/// statement reminder asks for it to be paid by the due date — the helper
/// text under the field says which of those will happen.
class PaidFromField extends StatelessWidget {
  final List<Account> accounts;
  final int? value;
  final ValueChanged<int?> onChanged;

  /// A withdrawal pays money back into the account rather than out of it.
  final bool withdrawal;

  const PaidFromField({
    super.key,
    required this.accounts,
    required this.value,
    required this.onChanged,
    this.withdrawal = false,
  });

  /// What saving against [account] will do, in one line.
  static String effectOf(Account? account, {bool withdrawal = false}) {
    if (account == null) return 'Not taken from any account balance';
    // Investments are recorded in the base currency; a foreign account
    // moves by the converted amount.
    final converted =
        account.isForeign ? ', converted to ${account.symbol}' : '';
    if (withdrawal) return 'Adds the amount back to ${account.name}$converted';
    if (account.type != 'credit_card') {
      return 'Lowers the ${account.name} balance by this amount$converted';
    }
    return account.hasBillingCycle
        ? 'Added to what you owe on ${account.name}: it is on the card\'s '
            'statement, and you\'ll be reminded to pay before the due date '
            '(the ${_ordinal(account.dueDay!)})'
        : 'Added to what you owe on ${account.name}. Set its statement and '
            'due day under Accounts to be reminded to pay it.';
  }

  static String _ordinal(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    switch (day % 10) {
      case 1:
        return '${day}st';
      case 2:
        return '${day}nd';
      case 3:
        return '${day}rd';
      default:
        return '${day}th';
    }
  }

  @override
  Widget build(BuildContext context) {
    // A deleted account matches no item, and a dropdown whose value matches
    // no item throws: show it as none instead.
    Account? selected;
    for (final a in accounts) {
      if (a.id == value) selected = a;
    }
    return DropdownButtonFormField<int?>(
      // Keyed on the value so a programmatic change (e.g. a preselected
      // default arriving after the first frame) is shown.
      key: ValueKey(selected?.id),
      initialValue: selected?.id,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: withdrawal ? 'Paid into' : 'Paid from',
        helperText: effectOf(selected, withdrawal: withdrawal),
        helperMaxLines: 3,
      ),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('None')),
        for (final a in accounts)
          DropdownMenuItem<int?>(
            value: a.id,
            child: Text(
              a.type == 'credit_card' ? '${a.name} (credit card)' : a.name,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
