part of '../credit_cards_screen.dart';

class _PeriodFilter extends StatelessWidget {
  final CardPeriodKind kind;
  final String? customLabel;
  final ValueChanged<CardPeriodKind> onSelected;
  final VoidCallback onCustom;
  const _PeriodFilter({
    required this.kind,
    required this.customLabel,
    required this.onSelected,
    required this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, CardPeriodKind k) => ChoiceChip(
          label: Text(label),
          selected: kind == k,
          onSelected: (_) => onSelected(k),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        chip('This cycle', CardPeriodKind.cycle),
        chip('This month', CardPeriodKind.thisMonth),
        chip('Last month', CardPeriodKind.lastMonth),
        ChoiceChip(
          avatar: const Icon(Icons.date_range, size: 18),
          label: Text(customLabel ?? 'Pick dates'),
          selected: kind == CardPeriodKind.custom,
          onSelected: (_) => onCustom(),
        ),
      ],
    );
  }
}

/// Combined figures across cards, when they share a currency and there is
/// more than one.
class _Totals extends StatelessWidget {
  final List<_CardFigures> rows;
  const _Totals({required this.rows});

  @override
  Widget build(BuildContext context) {
    final symbols = {for (final r in rows) r.summary.account.symbol};
    if (rows.length < 2 || symbols.length != 1) return const SizedBox.shrink();
    final symbol = symbols.single;
    final spent = rows.fold<int>(0, (s, r) => s + r.spent);
    final owed = rows.fold<int>(0, (s, r) => s + r.summary.owed);
    final limited = rows.where((r) => r.summary.limit != null).toList();
    // Cards sharing one limit have the same amount available; count it once.
    final byPool = <int, int>{};
    for (final r in limited) {
      byPool[_poolKey(r.summary)] = r.summary.available!;
    }
    final available = byPool.values.fold<int>(0, (s, v) => s + v);

    return Card(
      margin: const EdgeInsets.only(bottom: Space.sm),
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Row(
          children: [
            Expanded(
                child: _Figure(
                    label: 'Spent', value: formatMoneyIn(symbol, spent))),
            const SizedBox(width: Space.sm),
            Expanded(
                child: _Figure(
                    label: 'Owed now',
                    value: formatMoneyIn(symbol, owed),
                    color: expenseColor(context))),
            if (limited.isNotEmpty) const SizedBox(width: Space.sm),
            if (limited.isNotEmpty)
              Expanded(
                  child: _Figure(
                      label: 'Available',
                      value: formatMoneyIn(symbol, available),
                      color: incomeColor(context))),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Figure({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: FontSizes.caption, color: mutedTextColor(context))),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: TextStyle(
                  fontSize: FontSizes.bodyLarge,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ),
      ],
    );
  }
}

/// Which card to put a purchase on today: the one whose bill for it is due
/// furthest away, so the money stays interest-free longest.
class _BestCardBanner extends StatelessWidget {
  final CreditCardSummary summary;
  final DateTime now;
  const _BestCardBanner({required this.summary, required this.now});

  @override
  Widget build(BuildContext context) {
    final w = summary.purchaseToday(now)!;
    final scheme = Theme.of(context).colorScheme;
    final a = summary.account;
    return Card(
      margin: const EdgeInsets.only(bottom: Space.sm),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.star_outline, color: scheme.onSecondaryContainer),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Best card to use today: '
                      '${a.last4 == null ? a.name : '${a.name} ••${a.last4}'}',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSecondaryContainer)),
                  const SizedBox(height: Space.xxs),
                  Text(
                      'A purchase today is billed on '
                      '${formatCompactDate(w.statement)} and due '
                      '${formatCompactDate(w.due)} — ${w.interestFreeDays} '
                      'days interest-free, the longest of your cards.',
                      style: TextStyle(
                          fontSize: FontSizes.body,
                          color: scheme.onSecondaryContainer)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cards on one credit limit (a bank's Visa and RuPay pair) in one frame:
/// the shared limit's bar on top, then each card with its own spending,
/// amount owed and bill.
class _SharedLimitGroup extends StatelessWidget {
  final List<_CardFigures> rows;
  const _SharedLimitGroup({required this.rows});

  @override
  Widget build(BuildContext context) {
    final s = rows.first.summary;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: Space.sm),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: scheme.primaryContainer.withValues(alpha: 0.35),
            padding: const EdgeInsets.fromLTRB(
                Space.md, Space.md, Space.md, Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.link, size: 18, color: scheme.primary),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        'Shared limit · ${rows.length} cards',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, color: scheme.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                _PoolTotals(rows: rows),
                if (s.limit != null)
                  _UsageBar(summary: s)
                else
                  Padding(
                    padding: const EdgeInsets.only(top: Space.sm),
                    child: Text('No limit set yet — set it on either card',
                        style: TextStyle(
                            fontSize: FontSizes.caption,
                            color: mutedTextColor(context))),
                  ),
                if (rows.first.bankCheck != null)
                  _BankCheckLine(check: rows.first.bankCheck!),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _CardTile(figures: rows[i], pooled: true),
          ],
        ],
      ),
    );
  }
}

/// What the cards on one shared limit add up to: spent over the chosen
/// period, owed now, and what is left of the limit.
class _PoolTotals extends StatelessWidget {
  final List<_CardFigures> rows;
  const _PoolTotals({required this.rows});

  @override
  Widget build(BuildContext context) {
    final symbol = rows.first.summary.account.symbol;
    final spent = rows.fold<int>(0, (t, r) => t + r.spent);
    final owed = rows.fold<int>(0, (t, r) => t + r.summary.owed);
    final available = rows.first.summary.available;
    // Each card's own cycle can start on a different day.
    final labels = {for (final r in rows) r.range.label};
    final period = labels.length == 1 ? labels.single : "each card's cycle";
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _Figure(
              label: 'Total spent · $period',
              value: formatMoneyIn(symbol, spent)),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: _Figure(
            label: 'Total owed now',
            value: formatMoneyIn(symbol, owed),
            color: owed > 0 ? expenseColor(context) : null,
          ),
        ),
        if (available != null) ...[
          const SizedBox(width: Space.sm),
          Expanded(
            child: _Figure(
              label: 'Available',
              value: formatMoneyIn(symbol, available),
              color: incomeColor(context),
            ),
          ),
        ],
      ],
    );
  }
}

/// "HDFC Visa and HDFC RuPay may share one limit" — two unlinked cards from
/// the same bank, offered for linking in one tap.
class _TwinSuggestion extends StatelessWidget {
  final LimitTwinSuggestion suggestion;
  final VoidCallback onLink;
  final VoidCallback onDismiss;
  const _TwinSuggestion({
    required this.suggestion,
    required this.onLink,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a = suggestion.holder, b = suggestion.other;
    final limit = a.creditLimit ?? b.creditLimit;
    return Card(
      margin: const EdgeInsets.only(bottom: Space.sm),
      color: scheme.tertiaryContainer,
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(Space.md, Space.md, Space.sm, Space.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.link, color: scheme.onTertiaryContainer),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    'Do ${a.name} and ${b.name} share one credit limit?',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: scheme.onTertiaryContainer),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: Space.xxl, top: Space.xs),
              child: Text(
                'Banks often issue a Visa and a RuPay card on one limit. '
                'Linked, both show what is left of '
                '${limit == null ? 'it' : formatMoneyIn(a.symbol, limit)}.',
                style: TextStyle(
                    fontSize: FontSizes.body,
                    color: scheme.onTertiaryContainer),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                      onPressed: onDismiss, child: const Text('Not shared')),
                  FilledButton.tonalIcon(
                    onPressed: onLink,
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('Link them'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where the numbers come from, so a card that looks wrong can be fixed.
class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final muted = mutedTextColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.sm, Space.md, Space.sm, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: muted),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              'Spending is tracked automatically from the SMS alerts filed '
              'against a card (its last 4 digits route them) and the expenses '
              'you add with it. Bill payments recorded as a transfer to the '
              'card bring "owed" down. Two cards on one limit (a Visa and a '
              'RuPay card, say) can be linked from a card\'s menu or its '
              'set-up, and then show as one shared limit. Tap a card for its '
              'statement by cycle.',
              style: TextStyle(fontSize: FontSizes.caption, color: muted),
            ),
          ),
        ],
      ),
    );
  }
}
