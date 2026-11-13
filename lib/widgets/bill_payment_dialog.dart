import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/expense.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';
import '../utils/credit_card_summary.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/db_constants.dart';
import '../utils/font_sizes.dart';
import '../utils/dimens.dart';

/// Records paying [summary]'s card bill, so it stops showing as due: the
/// amount (the full due, the minimum, or any other), the day, and the account
/// it was paid from — or none, for an account the app does not track.
///
/// Saved as a transfer into the card: it brings "owed" down and does not
/// count as spending. Returns true when recorded.
Future<bool> showBillPaymentDialog(
    BuildContext context, CreditCardSummary summary,
    {DateTime? now}) async {
  final done = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _BillPaymentDialog(summary: summary, now: now ?? DateTime.now()),
  );
  return done ?? false;
}

class _BillPaymentDialog extends StatefulWidget {
  final CreditCardSummary summary;
  final DateTime now;
  const _BillPaymentDialog({required this.summary, required this.now});

  @override
  State<_BillPaymentDialog> createState() => _BillPaymentDialogState();
}

class _BillPaymentDialogState extends State<_BillPaymentDialog> {
  late final TextEditingController _amount;
  late DateTime _date;
  int? _fromId;
  bool _saving = false;

  CreditCardSummary get _s => widget.summary;
  Account get _card => _s.account;

  /// The earliest day a payment counts toward this bill.
  DateTime get _firstDay => _s.cycle?.statementDate ?? DateTime(2000);

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
        text: _s.dueRemaining > 0 ? minorToEditString(_s.dueRemaining) : '');
    _amount.addListener(() => setState(() {}));
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    _date = today.isBefore(_firstDay) ? _firstDay : today;
    // Paid from the default account when it is one a bill can be paid from.
    final accounts = context.read<AccountProvider>();
    int? defaultId;
    try {
      defaultId = context.read<SettingsProvider>().defaultAccountId;
    } on ProviderNotFoundException {
      defaultId = null; // no settings above this dialog (tests)
    }
    final def = accounts.accountById(defaultId);
    if (def != null && _payable(def)) _fromId = def.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// Accounts a card bill is paid from: not this card, not a loan.
  bool _payable(Account a) =>
      a.id != _card.id && !a.isLoan && !a.isLent && a.type != 'credit_card';

  int? get _parsed {
    final v = parseMinor(_amount.text.trim());
    return v == null || v <= 0 ? null : v;
  }

  Future<void> _save() async {
    final amount = _parsed;
    if (amount == null) return;
    setState(() => _saving = true);
    final expenses = context.read<ExpenseProvider>();
    final accounts = context.read<AccountProvider>();
    await expenses.addExpense(Expense(
      description: 'Card bill payment · ${_card.name}',
      amount: amount,
      date: _date,
      category: 'Transfer',
      paymentMode: 'Other',
      type: DbConstants.txTransfer,
      // None: paid from an account the app does not track.
      accountId: _fromId,
      toAccountId: _card.id,
    ));
    await accounts.refreshBalances();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final symbol = _card.symbol;
    final payable =
        context.watch<AccountProvider>().accounts.where(_payable).toList();
    final min = _s.minimumDueEstimate;
    final muted = mutedTextColor(context);
    return AlertDialog(
      title: Text('Mark ${_card.name} bill as paid'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_s.dueRemaining > 0)
              Text(
                  '${formatMoneyIn(symbol, _s.dueRemaining)} is due on the '
                  '${formatCompactDate(_s.cycle?.statementDate ?? _date)} '
                  'statement.',
                  style: TextStyle(fontSize: FontSizes.body, color: muted)),
            const SizedBox(height: Space.md),
            Wrap(
              spacing: 8,
              children: [
                if (_s.dueRemaining > 0)
                  ChoiceChip(
                    label:
                        Text('Full ${formatMoneyIn(symbol, _s.dueRemaining)}'),
                    selected: _parsed == _s.dueRemaining,
                    onSelected: (_) =>
                        _amount.text = minorToEditString(_s.dueRemaining),
                  ),
                if (min > 0 && min < _s.dueRemaining)
                  ChoiceChip(
                    label: Text('Minimum ~${formatMoneyIn(symbol, min)}'),
                    selected: _parsed == min,
                    onSelected: (_) => _amount.text = minorToEditString(min),
                  ),
              ],
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Amount paid ($symbol)',
                errorText: _amount.text.trim().isNotEmpty && _parsed == null
                    ? 'Enter an amount'
                    : null,
              ),
            ),
            const SizedBox(height: Space.md),
            DropdownButtonFormField<int?>(
              initialValue: _fromId,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Paid from',
                helperText: 'Its balance comes down by the amount',
                helperMaxLines: 2,
              ),
              items: [
                const DropdownMenuItem<int?>(
                    value: null, child: Text('Not tracked in the app')),
                for (final a in payable)
                  DropdownMenuItem<int?>(
                      value: a.id,
                      child: Text(a.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _fromId = v),
            ),
            const SizedBox(height: Space.sm),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(formatCompactDate(_date)),
              subtitle: const Text('Paid on'),
              onTap: () async {
                final today =
                    DateTime(widget.now.year, widget.now.month, widget.now.day);
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  // Earlier than the statement it would not pay this bill.
                  firstDate: _firstDay.isAfter(today) ? today : _firstDay,
                  lastDate: today,
                );
                if (picked != null) setState(() => _date = picked);
              },
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
          onPressed: _saving || _parsed == null ? null : _save,
          child: const Text('Mark as paid'),
        ),
      ],
    );
  }
}
