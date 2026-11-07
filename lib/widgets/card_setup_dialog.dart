import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../providers/account_provider.dart';
import '../utils/credit_card_summary.dart';
import '../utils/currency_format.dart';

/// Adds a credit card, or fills in what an existing one needs for tracking:
/// its limit, statement and due days, the last four digits SMS alerts quote,
/// what was already owed on it when tracking started, and — for a bank that
/// issues two cards on one limit, like a Visa and a RuPay card — which other
/// card it shares that limit with. Everything after
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

  /// Cards this one can share a limit with, and the card chosen (null: a
  /// limit of its own).
  late final List<Account> _partners;
  int? _sharesWith;

  /// Every credit card, by id, as the dialog opened.
  late final Map<int, Account> _cards;

  Account? get _card => widget.card;
  String get _symbol => _card?.symbol ?? CurrencyFormat.symbol;

  /// The card holding the limit of the pool [id] belongs to.
  Account? _holderOf(int? id) {
    final c = id == null ? null : _cards[id];
    return c == null ? null : limitHolderOf(c, _cards);
  }

  @override
  void initState() {
    super.initState();
    final c = _card;
    final all = context.read<AccountProvider>().accounts;
    _cards = {
      for (final a in all)
        if (a.type == 'credit_card' && a.id != null) a.id!: a
    };
    // Another card in the same currency, and not one already drawing on this
    // card's limit — choosing that would make the pair point at each other.
    _partners = [
      for (final a in _cards.values)
        if (a.id != c?.id &&
            a.currency == c?.currency &&
            (c?.id == null || _holderOf(a.id)?.id != c!.id))
          a
    ];
    final holder = c == null ? null : limitHolderOf(c, _cards);
    _sharesWith = holder != null && holder.id != c!.id ? holder.id : null;
    // Linked, the field edits the shared limit, which the holder carries.
    final limit = _sharesWith == null
        ? c?.creditLimit
        : (limitPools(all)[c!.id]?.limit ?? c.creditLimit);
    _name = TextEditingController(text: c?.name ?? '');
    _last4 = TextEditingController(text: c?.last4 ?? '');
    _limit = TextEditingController(
        text: limit == null ? '' : minorToEditString(limit));
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
    final parsed =
        _limit.text.trim().isEmpty ? null : parseMinor(_limit.text.trim());
    final limit = parsed == null || parsed <= 0 ? null : parsed;
    // Linking points at the card that carries the pool's limit.
    final holder = _holderOf(_sharesWith);
    final provider = context.read<AccountProvider>();
    if (holder != null && holder.creditLimit != limit) {
      // The shared limit lives on the holder: set it there.
      await provider.updateAccount(Account(
        id: holder.id,
        name: holder.name,
        type: holder.type,
        openingBalance: holder.openingBalance,
        color: holder.color,
        currency: holder.currency,
        rate: holder.rate,
        last4: holder.last4,
        statementDay: holder.statementDay,
        dueDay: holder.dueDay,
        creditLimit: limit,
        sharedLimitWith: holder.sharedLimitWith,
      ));
    }
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
      creditLimit: holder == null ? limit : null,
      sharedLimitWith: holder?.id,
    );
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
              if (_partners.isNotEmpty)
                DropdownButtonFormField<int?>(
                  initialValue: _sharesWith,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Shares limit with',
                    helperText: 'Two cards on one limit, like a Visa and a '
                        'RuPay card from the same bank',
                    helperMaxLines: 2,
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('No other card')),
                    for (final p in _partners)
                      DropdownMenuItem<int?>(
                        value: p.id,
                        child: Text(
                            p.last4 == null ? p.name : '${p.name} ••${p.last4}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    // Picking a card shows the limit it already carries.
                    final pick = _holderOf(v);
                    if (pick?.creditLimit != null) {
                      _limit.text = minorToEditString(pick!.creditLimit!);
                    }
                    _sharesWith = v;
                  }),
                ),
              TextFormField(
                controller: _limit,
                decoration: InputDecoration(
                  labelText: _sharesWith == null
                      ? 'Credit limit ($_symbol)'
                      : 'Shared credit limit ($_symbol)',
                  helperText: _sharesWith == null
                      ? 'Shows how much of it you have used'
                      : 'One limit for both cards: spending on either '
                          'uses it up',
                  helperMaxLines: 2,
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
