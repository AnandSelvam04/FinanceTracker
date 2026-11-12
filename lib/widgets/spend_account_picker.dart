import 'package:flutter/material.dart';

import '../models/account.dart';
import '../utils/app_colors.dart';
import 'paid_from_field.dart';
import '../utils/font_sizes.dart';

/// Where a spend was paid from: the account, and — when it went on a credit
/// card — which card, as one-tap chips. Shared by the Add Expense form and
/// the transaction edit sheet, so a card spend an SMS missed can be added by
/// hand, or moved to the right card, and still lands on that card's bill and
/// limit.
class SpendAccountPicker extends StatelessWidget {
  final List<Account> accounts;
  final int? accountId;
  final String paymentMode;

  /// Called with the new account and the payment mode that goes with it.
  final void Function(int? accountId, String paymentMode) onChanged;

  /// Hides the "Paid from" dropdown, for a form that has its own.
  final bool showDropdown;

  const SpendAccountPicker({
    super.key,
    required this.accounts,
    required this.accountId,
    required this.paymentMode,
    required this.onChanged,
    this.showDropdown = true,
  });

  static const creditCardMode = 'Credit Card';

  /// The payment mode an account of [type] implies, or null when it doesn't
  /// pin one down (a bank account may be a debit card, UPI, or a transfer).
  static String? modeFor(String? type) => switch (type) {
        'cash' => 'Cash',
        'credit_card' => creditCardMode,
        'upi' => 'UPI',
        _ => null,
      };

  /// The account to keep when the payment mode changes to [mode]. Choosing
  /// "Credit Card" picks the card when there is only one (else none, so the
  /// card row asks which); leaving it drops a card account for [fallbackId]
  /// (the default account), since the spend no longer went on a card.
  static int? accountForMode(
      String mode, int? accountId, List<Account> accounts,
      {int? fallbackId}) {
    Account? byId(int? id) {
      for (final a in accounts) {
        if (a.id == id) return a;
      }
      return null;
    }

    final current = byId(accountId);
    final cards = accounts.where((a) => a.type == 'credit_card').toList();
    if (mode == creditCardMode) {
      if (current?.type == 'credit_card') return accountId;
      return cards.length == 1 ? cards.single.id : null;
    }
    if (current?.type == 'credit_card') {
      final fallback = byId(fallbackId);
      return fallback != null && fallback.type != 'credit_card'
          ? fallback.id
          : null;
    }
    return accountId;
  }

  static String _label(Account a) {
    final digits = a.last4 == null ? '' : ' ••${a.last4}';
    return a.type == 'credit_card'
        ? '${a.name}$digits (credit card)'
        : '${a.name}$digits';
  }

  @override
  Widget build(BuildContext context) {
    Account? selected;
    for (final a in accounts) {
      if (a.id == accountId) selected = a;
    }
    final cards = accounts.where((a) => a.type == 'credit_card').toList();
    final onCard = paymentMode == creditCardMode;
    final muted = mutedTextColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDropdown)
          DropdownButtonFormField<int?>(
            // Keyed on the value so a change made by the card chips shows.
            key: ValueKey('paid-from-${selected?.id}'),
            initialValue: selected?.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Paid from'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('None')),
              for (final a in accounts)
                DropdownMenuItem<int?>(
                  value: a.id,
                  child: Text(_label(a), overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (id) {
              Account? picked;
              for (final a in accounts) {
                if (a.id == id) picked = a;
              }
              onChanged(id, modeFor(picked?.type) ?? paymentMode);
            },
          ),
        if (onCard) ...[
          const SizedBox(height: 12),
          Text('Which card?',
              style: TextStyle(fontSize: FontSizes.caption, color: muted)),
          const SizedBox(height: 6),
          if (cards.isEmpty)
            Text(
              'No credit card added yet. Add one under Credit cards so this '
              'counts toward its bill and limit.',
              style: TextStyle(
                  fontSize: FontSizes.caption, color: warningColor(context)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in cards)
                  ChoiceChip(
                    avatar: const Icon(Icons.credit_card, size: 18),
                    showCheckmark: false,
                    label: Text(
                        c.last4 == null ? c.name : '${c.name} ••${c.last4}'),
                    selected: c.id == accountId,
                    onSelected: (_) => onChanged(c.id, creditCardMode),
                  ),
              ],
            ),
          if (cards.isNotEmpty && selected?.type != 'credit_card')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Pick the card, or it won\'t count toward any card\'s bill',
                style: TextStyle(
                    fontSize: FontSizes.caption, color: warningColor(context)),
              ),
            ),
        ],
        if (selected != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(PaidFromField.effectOf(selected),
                style: TextStyle(fontSize: FontSizes.caption, color: muted)),
          ),
      ],
    );
  }
}
