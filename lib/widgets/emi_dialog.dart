import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/emi_plan.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../services/emi_service.dart';
import '../utils/app_colors.dart';
import '../utils/billing_cycle.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/font_sizes.dart';
import '../utils/dimens.dart';

/// Converts a purchase on [card] to EMI. Returns true when converted.
Future<bool> showEmiDialog(BuildContext context, Account card,
    {DateTime? now}) async {
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => _EmiDialog(card: card, now: now ?? DateTime.now()),
  );
  return done ?? false;
}

/// The usual tenures banks offer.
const emiTenures = [3, 6, 9, 12, 18, 24, 36];

/// When the first instalment of an EMI converted on [now] is billed: on the
/// card's next statement date when it has a billing cycle, else a month on.
DateTime firstInstalmentDate(Account card, DateTime now) {
  if (card.hasBillingCycle) {
    return computeCreditCardCycle(
            statementDay: card.statementDay!, dueDay: card.dueDay!, now: now)
        .nextStatementDate;
  }
  return DateTime(now.year, now.month + 1, now.day > 28 ? 28 : now.day);
}

class _EmiDialog extends StatefulWidget {
  final Account card;
  final DateTime now;
  const _EmiDialog({required this.card, required this.now});

  @override
  State<_EmiDialog> createState() => _EmiDialogState();
}

class _EmiDialogState extends State<_EmiDialog> {
  final _form = GlobalKey<FormState>();
  final _desc = TextEditingController();
  final _amount = TextEditingController();
  final _monthly = TextEditingController();
  int _months = 6;
  late DateTime _first;
  bool _recorded = true;

  /// The monthly field follows the amount (no-cost EMI) until edited.
  bool _monthlyEdited = false;
  bool _saving = false;

  String get _symbol => widget.card.symbol;

  @override
  void initState() {
    super.initState();
    _first = firstInstalmentDate(widget.card, widget.now);
    _amount.addListener(_syncMonthly);
  }

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    _monthly.dispose();
    super.dispose();
  }

  int? get _principal {
    final p = parseMinor(_amount.text.trim());
    return p == null || p <= 0 ? null : p;
  }

  int? get _monthlyAmount {
    final m = parseMinor(_monthly.text.trim());
    return m == null || m <= 0 ? null : m;
  }

  void _syncMonthly() {
    if (_monthlyEdited) {
      setState(() {});
      return;
    }
    final p = _principal;
    _monthly.text = p == null ? '' : minorToEditString((p / _months).ceil());
    setState(() {});
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    await EmiService.convert(
      card: widget.card,
      description: _desc.text.trim(),
      principal: _principal!,
      months: _months,
      monthlyAmount: _monthlyAmount!,
      firstDate: _first,
      convertedOn: widget.now,
      purchaseRecorded: _recorded,
    );
    await EmiService.postDue(now: widget.now);
    if (!mounted) return;
    await context.read<ExpenseProvider>().reloadLoadedYears();
    if (!mounted) return;
    await context.read<AccountProvider>().fetchAccounts();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final p = _principal, m = _monthlyAmount;
    final interest =
        p != null && m != null ? EmiPlan.interestFor(p, _months, m) : null;
    InputDecoration deco(String label, {String? helper}) => InputDecoration(
          border: const OutlineInputBorder(),
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
          errorMaxLines: 2,
        );
    return AlertDialog(
      title: Text('Convert to EMI · ${widget.card.name}'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Space.xs),
              TextFormField(
                controller: _desc,
                textCapitalization: TextCapitalization.sentences,
                decoration: deco('What was bought', helper: 'e.g. iPhone'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Describe the purchase' : null,
              ),
              const SizedBox(height: Space.md),
              TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: deco('Amount converted ($_symbol)'),
                validator: (_) => _principal == null ? 'Enter an amount' : null,
              ),
              const SizedBox(height: Space.md),
              Text('Months',
                  style: TextStyle(
                      fontSize: FontSizes.body,
                      color: mutedTextColor(context))),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final n in emiTenures)
                    ChoiceChip(
                      label: Text('$n'),
                      selected: _months == n,
                      onSelected: (_) {
                        _months = n;
                        _syncMonthly();
                      },
                    ),
                ],
              ),
              const SizedBox(height: Space.md),
              TextFormField(
                controller: _monthly,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() => _monthlyEdited = true),
                decoration: deco('Monthly EMI ($_symbol)',
                    helper: 'As the bank shows it, interest included. Left '
                        'as is, it is a no-cost EMI.'),
                validator: (_) {
                  if (_monthlyAmount == null) return 'Enter the monthly EMI';
                  if (p != null && _monthlyAmount! * _months < p) {
                    return 'Too low: $_months instalments must cover the '
                        'amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: Space.sm),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(formatCompactDate(_first)),
                subtitle: const Text('First instalment billed'),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _first,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(widget.now.year + 3),
                  );
                  if (picked != null) setState(() => _first = picked);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _recorded,
                onChanged: (v) => setState(() => _recorded = v),
                title: const Text('The purchase is already in the app'),
                subtitle: Text(
                  _recorded
                      ? 'It comes off the card now, as the bank reverses it'
                      : 'An EMI from before you started tracking: enter what '
                          'is left and the months to go',
                  style: const TextStyle(fontSize: FontSizes.caption),
                ),
              ),
              if (p != null && m != null && interest != null)
                Container(
                  margin: const EdgeInsets.only(top: Space.sm),
                  padding: const EdgeInsets.all(Space.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    '${formatMoneyIn(_symbol, m)} a month for $_months '
                    'months, on the card\'s bill from '
                    '${formatCompactDate(_first)}. '
                    '${interest > 0 ? 'Interest ${formatMoneyIn(_symbol, interest)} in all. ' : 'No-cost EMI. '}'
                    '${formatMoneyIn(_symbol, p)} stays held on the limit and '
                    'frees up as instalments are billed.',
                    style: const TextStyle(fontSize: FontSizes.body),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Convert'),
        ),
      ],
    );
  }
}
