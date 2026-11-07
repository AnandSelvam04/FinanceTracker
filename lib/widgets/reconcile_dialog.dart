import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../providers/account_provider.dart';
import '../utils/app_colors.dart';
import '../utils/credit_card_summary.dart';
import '../utils/currency_format.dart';

/// What the bank's figure for a credit card is: what is owed on it, or how
/// much of its limit is left.
enum ReconcileFigure { owed, available }

/// The balance [account] must have for the bank's [figure] of [amount] to
/// hold. For a card's available limit, the other cards on a shared limit
/// keep what they owe, so this card takes up the rest. Null when the
/// figure cannot be placed (an available limit on a card without a limit).
int? reconcileTarget({
  required Account account,
  required ReconcileFigure figure,
  required int amount,
  required List<Account> accounts,
  required int? Function(Account) balanceOf,
}) {
  final isCard = account.type == 'credit_card';
  if (!isCard) return amount;
  if (figure == ReconcileFigure.owed) return -amount;
  final pool = limitPools(accounts)[account.id];
  final limit = pool?.limit ??
      (account.creditLimit != null && account.creditLimit! > 0
          ? account.creditLimit
          : null);
  if (limit == null) return null;
  var othersOwed = 0;
  for (final c in pool?.others(account) ?? const <Account>[]) {
    final b = balanceOf(c) ?? 0;
    if (b < 0) othersOwed += -b;
  }
  // limit − (this card's owed + others' owed) = available.
  final owed = limit - amount - othersOwed;
  return -owed;
}

/// Makes an account's balance match the bank: enter what the bank (or card
/// app, or an SMS) shows today, and the app moves the account's starting
/// balance by the difference. Transactions, spending and budgets are left
/// exactly as they are.
///
/// For a credit card the bank's figure can be the amount outstanding or the
/// available limit (what card SMS alerts quote as "Avl Lmt"). [figure] and
/// [initialAmount] pre-fill it. Returns true when the balance was changed.
Future<bool> showReconcileDialog(BuildContext context, Account account,
    {ReconcileFigure? figure, int? initialAmount}) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => _ReconcileDialog(
        account: account, figure: figure, initialAmount: initialAmount),
  );
  return changed ?? false;
}

class _ReconcileDialog extends StatefulWidget {
  final Account account;
  final ReconcileFigure? figure;
  final int? initialAmount;
  const _ReconcileDialog(
      {required this.account, this.figure, this.initialAmount});

  @override
  State<_ReconcileDialog> createState() => _ReconcileDialogState();
}

class _ReconcileDialogState extends State<_ReconcileDialog> {
  late final TextEditingController _amount;
  late ReconcileFigure _figure;
  bool _saving = false;

  Account get _account => widget.account;
  bool get _isCard => _account.type == 'credit_card';

  @override
  void initState() {
    super.initState();
    _figure = widget.figure ?? ReconcileFigure.owed;
    _amount = TextEditingController(
        text: widget.initialAmount == null
            ? ''
            : minorToEditString(widget.initialAmount!));
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AccountProvider>();
    final account = provider.accountById(_account.id) ?? _account;
    final symbol = account.symbol;
    final current = provider.balanceOf(account) ?? account.openingBalance;
    final hasLimit =
        _isCard && (limitPools(provider.accounts)[account.id]?.limit != null);
    final text = _amount.text.trim();
    final parsed = text.isEmpty ? null : parseMinor(text);
    final valid = parsed != null && (_isCard ? parsed >= 0 : true);
    final target = valid
        ? reconcileTarget(
            account: account,
            figure: _figure,
            amount: parsed,
            accounts: provider.accounts,
            balanceOf: provider.balanceOf)
        : null;
    final delta = target == null ? null : target - current;
    final muted = mutedTextColor(context);

    String describe(int balance) => _isCard
        ? (balance <= 0
            ? '${formatMoneyIn(symbol, -balance)} owed'
            : '${formatMoneyIn(symbol, balance)} credit')
        : formatMoneySignedIn(symbol, balance);

    return AlertDialog(
      title: const Text('Match bank balance'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('The app shows ${describe(current)}. Enter what your bank '
                'shows today.'),
            const SizedBox(height: 16),
            if (_isCard && hasLimit) ...[
              SegmentedButton<ReconcileFigure>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: ReconcileFigure.owed, label: Text('Outstanding')),
                  ButtonSegment(
                      value: ReconcileFigure.available,
                      label: Text('Available limit')),
                ],
                selected: {_figure},
                onSelectionChanged: (v) => setState(() => _figure = v.first),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _amount,
              autofocus: widget.initialAmount == null,
              keyboardType: TextInputType.numberWithOptions(
                  decimal: true, signed: !_isCard),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: !_isCard
                    ? 'Balance in the bank ($symbol)'
                    : _figure == ReconcileFigure.owed
                        ? 'Total outstanding ($symbol)'
                        : 'Available limit ($symbol)',
                helperText: _isCard && _figure == ReconcileFigure.available
                    ? 'As card SMS alerts quote it: "Avl Lmt"'
                    : null,
                errorText: text.isNotEmpty && !valid ? 'Invalid amount' : null,
              ),
            ),
            const SizedBox(height: 12),
            if (delta != null)
              Text(
                delta == 0
                    ? 'Already matches — nothing to change.'
                    : 'The starting balance moves by '
                        '${formatMoneySignedIn(symbol, delta)} so the app '
                        'shows ${describe(target!)}. Transactions, spending '
                        'and budgets stay as they are.',
                style: TextStyle(fontSize: 13, color: muted),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || delta == null || delta == 0
              ? null
              : () async {
                  setState(() => _saving = true);
                  await context
                      .read<AccountProvider>()
                      .setBalance(account, target!);
                  if (context.mounted) Navigator.pop(context, true);
                },
          child: const Text('Match'),
        ),
      ],
    );
  }
}
