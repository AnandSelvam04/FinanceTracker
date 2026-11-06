import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../providers/account_provider.dart';
import '../utils/currency_format.dart';

/// Adds a credit card, or fills in what an existing one needs for tracking:
/// its limit, statement and due days, the last four digits SMS alerts quote,
/// and what was already owed on it when tracking started. Everything after
/// that — purchases from SMS alerts or added by hand, bill payments — moves
/// the figures on its own.
///
/// Returns true when the card was saved.
Future<bool> showCardSetupDialog(BuildContext context, {Account? card}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _CardSetupDialog(card: card),
  );
  return saved ?? false;
}

class _CardSetupDialog extends StatefulWidget {
  final Account? card;
  const _CardSetupDialog({this.card});

  @override
  State<_CardSetupDialog> createState() => _CardSetupDialogState();
}

class _CardSetupDialogState extends State<_CardSetupDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _last4;
  late final TextEditingController _limit;
  late final TextEditingController _statementDay;
  late final TextEditingController _dueDay;
  late final TextEditingController _owed;
  bool _saving = false;

  Account? get _card => widget.card;
  String get _symbol => _card?.symbol ?? CurrencyFormat.symbol;

  @override
  void initState() {
    super.initState();
    final c = _card;
    _name = TextEditingController(text: c?.name ?? '');
    _last4 = TextEditingController(text: c?.last4 ?? '');
    _limit = TextEditingController(
        text: c?.creditLimit == null ? '' : minorToEditString(c!.creditLimit!));
    _statementDay = TextEditingController(text: c?.statementDay?.toString());
    _dueDay = TextEditingController(text: c?.dueDay?.toString());
    // A card's opening balance is negative while something is owed on it.
    final opening = c?.openingBalance ?? 0;
    _owed = TextEditingController(
        text: opening < 0 ? minorToEditString(-opening) : '');
  }

  @override
  void dispose() {
    for (final c in [_name, _last4, _limit, _statementDay, _dueDay, _owed]) {
      c.dispose();
    }
    super.dispose();
  }

  static int? _day(String text) =>
      text.trim().isEmpty ? null : int.tryParse(text.trim());

  String? _dayError(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    return (n == null || n < 1 || n > 28) ? 'A day 1–28' : null;
  }

  String? _amountError(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    final n = parseMinor(t);
    if (n == null) return 'Invalid amount';
    return n < 0 ? 'Enter a positive amount' : null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final c = _card;
    final owedText = _owed.text.trim();
    final opening = owedText.isEmpty
        // Left blank: keep a credit the card already started with.
        ? ((c?.openingBalance ?? 0) > 0 ? c!.openingBalance : 0)
        : -(parseMinor(owedText) ?? 0);
    final limit =
        _limit.text.trim().isEmpty ? null : parseMinor(_limit.text.trim());
    final account = Account(
      id: c?.id,
      name: _name.text.trim(),
      type: 'credit_card',
      openingBalance: opening,
      color: c?.color,
      currency: c?.currency,
      rate: c?.rate ?? 1.0,
      last4: _last4.text.trim().isEmpty ? null : _last4.text.trim(),
      statementDay: _day(_statementDay.text),
      dueDay: _day(_dueDay.text),
      creditLimit: limit == null || limit <= 0 ? null : limit,
    );
    final provider = context.read<AccountProvider>();
    if (c == null) {
      await provider.addAccount(account);
    } else {
      await provider.updateAccount(account);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          Text(_card == null ? 'Add a credit card' : 'Set up ${_card!.name}'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Card name'),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Give the card a name' : null,
              ),
              TextFormField(
                controller: _last4,
                decoration: const InputDecoration(
                  labelText: 'Last 4 digits',
                  helperText: 'So SMS alerts are filed against this card',
                  counterText: '',
                ),
                keyboardType: TextInputType.number,
                maxLength: 4,
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return null;
                  return RegExp(r'^\d{4}$').hasMatch(t)
                      ? null
                      : 'Enter exactly 4 digits';
                },
              ),
              TextFormField(
                controller: _limit,
                decoration: InputDecoration(
                  labelText: 'Credit limit ($_symbol)',
                  helperText: 'Shows how much of it you have used',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: _amountError,
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _statementDay,
                      decoration: const InputDecoration(
                        labelText: 'Statement day',
                        helperText: 'Bill generated',
                        counterText: '',
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 2,
                      validator: _dayError,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _dueDay,
                      decoration: const InputDecoration(
                        labelText: 'Due day',
                        helperText: 'Payment due',
                        counterText: '',
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 2,
                      validator: (v) {
                        final own = _dayError(v);
                        if (own != null) return own;
                        // One without the other can't place a bill.
                        final hasStatement =
                            _statementDay.text.trim().isNotEmpty;
                        final hasDue = (v ?? '').trim().isNotEmpty;
                        return hasStatement != hasDue ? 'Set both days' : null;
                      },
                    ),
                  ),
                ],
              ),
              TextFormField(
                controller: _owed,
                decoration: InputDecoration(
                  labelText: 'Already owed when you start ($_symbol)',
                  helperText: 'The card\'s outstanding before the first '
                      'transaction you record here',
                  helperMaxLines: 2,
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: _amountError,
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
          child: const Text('Save'),
        ),
      ],
    );
  }
}
