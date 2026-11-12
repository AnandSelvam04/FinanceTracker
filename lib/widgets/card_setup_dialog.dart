import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../providers/account_provider.dart';
import '../utils/app_colors.dart';
import '../utils/credit_card_summary.dart';
import '../utils/currency_format.dart';
import '../utils/font_sizes.dart';

/// Adds a credit card, or fills in what an existing one needs for tracking:
/// its limit, statement and due days, the last four digits SMS alerts quote,
/// what was already owed on it when tracking started, and — for a bank that
/// issues two cards on one limit, like a Visa and a RuPay card — which other
/// card it shares that limit with. Everything after that — purchases from SMS
/// alerts or added by hand, bill payments — moves the figures on its own.
///
/// Opens full screen, in sections, so the fields and their help text have
/// room even with a large system font. [linkTo] opens it already set to
/// share that card's limit (adding a card's twin); [startShared] opens it on
/// "Shared" for the user to pick the other card.
///
/// Returns true when the card was saved.
Future<bool> showCardSetupDialog(BuildContext context,
    {Account? card, Account? linkTo, bool startShared = false}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _CardSetupDialog(card: card, linkTo: linkTo, startShared: startShared),
  );
  return saved ?? false;
}

class _CardSetupDialog extends StatefulWidget {
  final Account? card;
  final Account? linkTo;
  final bool startShared;
  const _CardSetupDialog({this.card, this.linkTo, this.startShared = false});

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
  late final TextEditingController _points;
  late final TextEditingController _rate;
  late final TextEditingController _pointValue;
  bool _saving = false;

  /// Cards this one can share a limit with.
  late final List<Account> _partners;

  /// Whether the card shares another card's limit, and which card.
  bool _shared = false;
  int? _sharesWith;

  /// Set when the billing days were filled in from the linked card.
  String? _daysCopiedFrom;

  /// Every credit card, by id, as the form opened.
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
    // One entry per pool: the card holding its limit.
    final seen = <int>{};
    _partners = [
      for (final a in _cards.values)
        if (a.id != c?.id &&
            a.currency == c?.currency &&
            (c?.id == null || _holderOf(a.id)?.id != c!.id) &&
            seen.add(_holderOf(a.id)!.id!))
          _holderOf(a.id)!
    ];
    final holder = c == null ? null : limitHolderOf(c, _cards);
    _sharesWith = holder != null && holder.id != c!.id ? holder.id : null;
    if (_sharesWith == null && widget.linkTo != null) {
      _sharesWith = _holderOf(widget.linkTo!.id)?.id;
    }
    _shared =
        _sharesWith != null || (widget.startShared && _partners.isNotEmpty);
    if (_shared && _sharesWith == null && _partners.length == 1) {
      _sharesWith = _partners.single.id;
    }
    // Linked, the field edits the shared limit, which the holder carries.
    final limit = _sharesWith == null
        ? c?.creditLimit
        : (limitPools(all)[_sharesWith]?.limit ?? c?.creditLimit);
    _name = TextEditingController(text: c?.name ?? '');
    _last4 = TextEditingController(text: c?.last4 ?? '');
    _limit = TextEditingController(
        text: limit == null ? '' : minorToEditString(limit));
    _statementDay = TextEditingController(text: c?.statementDay?.toString());
    _dueDay = TextEditingController(text: c?.dueDay?.toString());
    // A card's opening balance is negative while something is owed on it.
    final opening = c?.openingBalance ?? 0;
    _points = TextEditingController(text: c?.rewardPoints?.toString() ?? '');
    _rate = TextEditingController(text: _num(c?.rewardRate));
    _pointValue = TextEditingController(text: _num(c?.pointValue));
    _owed = TextEditingController(
        text: opening < 0 ? minorToEditString(-opening) : '');
    if (_sharesWith != null && _sharesWith != c?.sharedLimitWith) {
      _copyDaysFrom(_cards[_sharesWith]!);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _last4,
      _limit,
      _statementDay,
      _dueDay,
      _owed,
      _points,
      _rate,
      _pointValue
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Cards on one limit normally bill together: fill blank billing days in
  /// from the card being linked to.
  void _copyDaysFrom(Account partner) {
    if (!partner.hasBillingCycle) return;
    if (_statementDay.text.trim().isNotEmpty ||
        _dueDay.text.trim().isNotEmpty) {
      return;
    }
    _statementDay.text = '${partner.statementDay}';
    _dueDay.text = '${partner.dueDay}';
    _daysCopiedFrom = partner.name;
  }

  void _pickPartner(int? id) {
    setState(() {
      _sharesWith = id;
      final pick = _holderOf(id);
      if (pick == null) return;
      // Show the limit the chosen card already carries.
      final limit = limitPools(_cards.values.toList())[pick.id]?.limit;
      if (limit != null) _limit.text = minorToEditString(limit);
      _copyDaysFrom(pick);
    });
  }

  /// A decimal for a field, without a trailing ".0".
  static String _num(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  static String? _positiveNumber(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final n = double.tryParse(t);
    return n == null || n < 0 ? 'A number, 0 or more' : null;
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
    if (_shared && _sharesWith == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pick the card this one shares its limit with')));
      return;
    }
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
    final holder = _shared ? _holderOf(_sharesWith) : null;
    final provider = context.read<AccountProvider>();
    if (holder != null && holder.creditLimit != limit) {
      // The shared limit lives on the holder: set it there.
      await provider.updateAccount(limit == null
          ? holder.copyWith(clearCreditLimit: true)
          : holder.copyWith(creditLimit: limit));
    }
    final points = int.tryParse(_points.text.trim().replaceAll(',', ''));
    final account = Account(
      rewardPoints: points,
      // A balance typed in now is as of today; one left alone keeps its date.
      rewardAsOf: points == null
          ? null
          : (points == c?.rewardPoints && c?.rewardAsOf != null
              ? c!.rewardAsOf
              : DateTime.now()),
      rewardRate: double.tryParse(_rate.text.trim()),
      pointValue: double.tryParse(_pointValue.text.trim()),
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

  InputDecoration _field(String label, {String? helper, String? hint}) =>
      InputDecoration(
        labelText: label,
        helperText: helper,
        hintText: hint,
        helperMaxLines: 3,
        errorMaxLines: 2,
        border: const OutlineInputBorder(),
        counterText: '',
      );

  @override
  Widget build(BuildContext context) {
    final title = _card?.name ?? 'New credit card';
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: _saving ? null : () => Navigator.pop(context, false),
          ),
          title: Text(title, overflow: TextOverflow.ellipsis),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
        body: Form(
          key: _form,
          // Not a lazy ListView: every field must be built for the form to
          // validate it.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionTitle('Card'),
                TextFormField(
                  controller: _name,
                  decoration: _field('Card name', hint: 'e.g. HDFC Visa'),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Give the card a name' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _last4,
                  decoration: _field('Last 4 digits',
                      helper: 'So SMS alerts are filed against this card'),
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
                const _SectionTitle('Credit limit'),
                if (_partners.isNotEmpty) ...[
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: false,
                          icon: Icon(Icons.credit_card),
                          label: Text('Own limit')),
                      ButtonSegment(
                          value: true,
                          icon: Icon(Icons.link),
                          label: Text('Shared')),
                    ],
                    selected: {_shared},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => setState(() {
                      _shared = v.first;
                      if (_shared &&
                          _sharesWith == null &&
                          _partners.length == 1) {
                        _pickPartner(_partners.single.id);
                      }
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_shared) ...[
                  Text(
                    'Pick the other card on this limit — like the Visa and '
                    'RuPay cards a bank issues together. Spending on either '
                    'uses up the one limit; each card keeps its own bill.',
                    style: TextStyle(
                        fontSize: FontSizes.body,
                        color: mutedTextColor(context)),
                  ),
                  const SizedBox(height: 8),
                  for (final p in _partners)
                    _PartnerTile(
                      card: p,
                      limit: limitPools(_cards.values.toList())[p.id]?.limit,
                      others: limitPools(_cards.values.toList())[p.id]
                              ?.others(p)
                              .where((o) => o.id != _card?.id)
                              .toList() ??
                          const [],
                      selected: _sharesWith == p.id,
                      onTap: () => _pickPartner(p.id),
                    ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _limit,
                  decoration: _field(
                    _shared
                        ? 'Shared credit limit ($_symbol)'
                        : 'Credit limit ($_symbol)',
                    helper: _shared
                        ? 'One limit for both cards. Changing it here changes '
                            'it for both.'
                        : 'Shows how much of it you have used',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: _amountError,
                ),
                if (_partners.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Have a second card on the same limit (a RuPay card with '
                      'your Visa)? Add it too, then choose "Shared" here to '
                      'link them.',
                      style: TextStyle(
                          fontSize: FontSizes.body,
                          color: mutedTextColor(context)),
                    ),
                  ),
                const _SectionTitle('Billing cycle'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _statementDay,
                        decoration:
                            _field('Statement day', helper: 'Bill generated'),
                        keyboardType: TextInputType.number,
                        maxLength: 2,
                        validator: _dayError,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _dueDay,
                        decoration: _field('Due day', helper: 'Payment due'),
                        keyboardType: TextInputType.number,
                        maxLength: 2,
                        validator: (v) {
                          final own = _dayError(v);
                          if (own != null) return own;
                          // One without the other can't place a bill.
                          final hasStatement =
                              _statementDay.text.trim().isNotEmpty;
                          final hasDue = (v ?? '').trim().isNotEmpty;
                          return hasStatement != hasDue
                              ? 'Set both days'
                              : null;
                        },
                      ),
                    ),
                  ],
                ),
                if (_daysCopiedFrom != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        'Copied from $_daysCopiedFrom — change them if '
                        'this card bills on other days.',
                        style: TextStyle(
                            fontSize: FontSizes.body,
                            color: mutedTextColor(context))),
                  ),
                const _SectionTitle('Reward points (optional)'),
                TextFormField(
                  controller: _points,
                  keyboardType: TextInputType.number,
                  decoration: _field('Points balance now',
                      helper: 'From the card app or statement. The app adds '
                          'what you earn from here on.'),
                  validator: (v) {
                    final t = (v ?? '').trim().replaceAll(',', '');
                    if (t.isEmpty) return null;
                    final n = int.tryParse(t);
                    return n == null || n < 0
                        ? 'Whole points, 0 or more'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _rate,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: _field('Points per ₹100',
                            hint: 'e.g. 4', helper: 'Earn rate'),
                        validator: _positiveNumber,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _pointValue,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: _field('₹ per point',
                            hint: 'e.g. 0.25', helper: 'What 1 point is worth'),
                        validator: _positiveNumber,
                      ),
                    ),
                  ],
                ),
                const _SectionTitle('Starting balance'),
                TextFormField(
                  controller: _owed,
                  decoration: _field(
                    'Already owed when you start ($_symbol)',
                    helper: 'The card\'s outstanding before the first '
                        'transaction you record here',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: _amountError,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Text(text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600)),
    );
  }
}

/// One card to share a limit with: its name and digits, and the limit it
/// carries (and any card already on it).
class _PartnerTile extends StatelessWidget {
  final Account card;
  final int? limit;
  final List<Account> others;
  final bool selected;
  final VoidCallback onTap;
  const _PartnerTile({
    required this.card,
    required this.limit,
    required this.others,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detail = [
      limit == null
          ? 'No limit set yet'
          : 'Limit ${formatMoneyIn(card.symbol, limit!)}',
      if (others.isNotEmpty) 'with ${others.map((o) => o.name).join(', ')}',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: selected ? scheme.secondaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1),
      ),
      child: ListTile(
        onTap: onTap,
        selected: selected,
        leading: Icon(selected ? Icons.check_circle : Icons.circle_outlined,
            color: selected ? scheme.primary : scheme.outline),
        title: Text(
            card.last4 == null ? card.name : '${card.name} ••${card.last4}'),
        subtitle: Text(detail),
      ),
    );
  }
}
