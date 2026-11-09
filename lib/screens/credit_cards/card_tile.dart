part of '../credit_cards_screen.dart';

class _CardTile extends StatelessWidget {
  final _CardFigures figures;

  /// Shown inside a [_SharedLimitGroup], which draws the card frame and the
  /// shared limit's bar itself.
  final bool pooled;
  const _CardTile({required this.figures, this.pooled = false});

  /// Where the last bill stands, and how urgent it is; null without a cycle.
  (String, Color?)? _billStatus(BuildContext context) {
    final s = figures.summary;
    if (!s.hasCycle) return null;
    final symbol = s.account.symbol;
    final cycle = s.cycle!;
    if (s.dueRemaining > 0) {
      final amount = formatMoneyIn(symbol, s.dueRemaining);
      final days = s.daysUntilDue!;
      if (days < 0) {
        return (
          '$amount overdue by ${-days} day${days == -1 ? '' : 's'}',
          dangerColor(context)
        );
      }
      if (days == 0) return ('$amount due today', dangerColor(context));
      return (
        '$amount due ${formatCompactDate(cycle.dueDate)} · '
            'in $days day${days == 1 ? '' : 's'}',
        days <= 7 ? warningColor(context) : null
      );
    }
    final next = 'next statement ${formatCompactDate(cycle.nextStatementDate)}';
    if (s.billPaid) return ('Bill paid ✓ · $next', incomeColor(context));
    return ('Nothing billed · $next', null);
  }

  @override
  Widget build(BuildContext context) {
    final s = figures.summary;
    final account = s.account;
    final symbol = account.symbol;
    final muted = mutedTextColor(context);
    final scheme = Theme.of(context).colorScheme;
    final own = account.color == null ? null : Color(account.color!);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final window = figures.now == null ? null : s.purchaseToday(figures.now!);
    final bill = _billStatus(context);
    // What this card still needs before it can be tracked fully.
    final missing = [
      if (s.limit == null) 'credit limit',
      if (!s.hasCycle) 'statement & due days',
      if (account.last4 == null) 'last 4 digits',
    ];

    final body = InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              AccountDetailScreen(account: account, showActions: false),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: own == null
                      ? scheme.secondaryContainer
                      : own.withValues(alpha: dark ? 0.28 : 0.15),
                  child: Icon(Icons.credit_card,
                      size: 20, color: own ?? scheme.onSecondaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    [
                      account.name,
                      if (account.last4 != null) '••${account.last4}'
                    ].join(' '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.tune),
                  tooltip: 'Set up ${account.name}',
                  onPressed: () => showCardSetupDialog(context, card: account),
                ),
                _CardMenu(summary: s),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: _Figure(
                            label: 'Spent · ${figures.range.label}',
                            value: formatMoneyIn(symbol, figures.spent)),
                      ),
                      Expanded(
                        child: _Figure(
                          label: 'Owed now',
                          value: s.credit > 0
                              ? '${formatMoneyIn(symbol, s.credit)} credit'
                              : formatMoneyIn(symbol, s.owed),
                          color: s.owed > 0 ? expenseColor(context) : null,
                        ),
                      ),
                    ],
                  ),
                  if (figures.paidIn > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                          'Paid in ${formatMoneyIn(symbol, figures.paidIn)} '
                          'in this period',
                          style: TextStyle(
                              fontSize: 12, color: incomeColor(context))),
                    ),
                  // Up top, where it is seen before buying: when a purchase
                  // on this card today has to be paid.
                  if (window != null)
                    _BuyTodayPill(
                        due: window.due, days: window.interestFreeDays),
                  if (s.owesMoreThanCycle) _OwedExplainer(summary: s),
                  if (s.limit != null && !pooled) _UsageBar(summary: s),
                  if (!pooled && figures.bankCheck != null)
                    _BankCheckLine(check: figures.bankCheck!),
                  if (bill != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(bill.$1,
                          style: TextStyle(
                              fontSize: 13,
                              color: bill.$2 ?? muted,
                              fontWeight: bill.$2 == null
                                  ? FontWeight.normal
                                  : FontWeight.w600)),
                    ),
                  if (s.dueRemaining > 0 &&
                      s.minimumDueEstimate > 0 &&
                      s.minimumDueEstimate < s.dueRemaining)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                          'Minimum due about '
                          '${formatMoneyIn(symbol, s.minimumDueEstimate)} — '
                          'paying only that leaves the rest charged interest',
                          style: TextStyle(fontSize: 12, color: muted)),
                    ),
                  if (s.dueRemaining > 0) ...[
                    for (final e in figures.paymentGuesses)
                      _PaymentGuess(expense: e, card: account),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: FilledButton.tonalIcon(
                        icon: const Icon(Icons.task_alt, size: 18),
                        label: const Text('Mark as paid'),
                        onPressed: () =>
                            showBillPaymentDialog(context, s, now: figures.now),
                      ),
                    ),
                  ],
                  if (figures.rewards != null)
                    _RewardsLine(estimate: figures.rewards!, symbol: symbol),
                  if (missing.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: Text('Add ${missing.join(', ')}',
                            maxLines: 3, softWrap: true),
                        onPressed: () =>
                            showCardSetupDialog(context, card: account),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (pooled) return body;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: body,
    );
  }
}

/// "Why ₹42,000 owed?" — shown when more is owed than went on the card this
/// cycle. Opens a breakdown that adds up to the amount owed: what was owed
/// when tracking began, what is left over from earlier cycles (usually the
/// last bill), this cycle's spending and payments — with a pointer to the
/// likely cause when the number looks too high.
class _OwedExplainer extends StatefulWidget {
  final CreditCardSummary summary;
  const _OwedExplainer({required this.summary});

  @override
  State<_OwedExplainer> createState() => _OwedExplainerState();
}

class _OwedExplainerState extends State<_OwedExplainer> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final symbol = s.account.symbol;
    final muted = mutedTextColor(context);
    final scheme = Theme.of(context).colorScheme;
    String money(int v) => formatMoneyIn(symbol, v);
    final since = formatCompactDate(s.periodStart);

    final lines = <(String, String, Color?)>[
      if (s.openingOwed != 0)
        s.openingOwed > 0
            ? ('Already owed when you started', money(s.openingOwed), null)
            : ('Credit when you started', '− ${money(-s.openingOwed)}', null),
      if (s.carriedFromEarlier != 0)
        s.carriedFromEarlier > 0
            ? (
                s.hasCycle
                    ? 'Earlier spending not yet paid off'
                    : 'Spent before this month, not yet paid off',
                money(s.carriedFromEarlier),
                null
              )
            : (
                'Paid in earlier beyond what was spent',
                '− ${money(-s.carriedFromEarlier)}',
                null
              ),
      if (s.cycleSpend != 0) ('Spent since $since', money(s.cycleSpend), null),
      if (s.paidThisPeriod != 0)
        (
          'Paid since $since',
          '− ${money(s.paidThisPeriod)}',
          incomeColor(context)
        ),
    ];

    // What most likely makes the figure higher than expected.
    final hints = <String>[
      if (s.hasCycle && s.dueRemaining > 0)
        '${money(s.dueRemaining)} of it is the bill from the '
            '${formatCompactDate(s.cycle!.statementDate)} statement, due '
            '${formatCompactDate(s.cycle!.dueDate)}. It stays in "owed" '
            'until you record paying it.',
      if (s.openingOwed > 0 && s.carriedFromEarlier > 0)
        'If the ${money(s.openingOwed)} you entered as already owed '
            'includes purchases that were also imported or added here, they '
            'are counted twice — lower it in the card\'s set-up.',
      if (s.carriedFromEarlier > 0 &&
          (!s.hasCycle || s.carriedFromEarlier > s.dueRemaining))
        'Paid an earlier bill? Record it as a transfer from your bank to '
            'this card so it comes off what is owed.',
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.help_outline, size: 16, color: scheme.primary),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Why ${money(s.owed)} owed when '
                      '${money(s.cycleSpend)} was spent this '
                      '${s.hasCycle ? 'cycle' : 'month'}?',
                      style: TextStyle(fontSize: 12, color: scheme.primary),
                    ),
                  ),
                  Icon(_open ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: scheme.primary),
                ],
              ),
            ),
          ),
          if (_open)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: Text(l.$1,
                                  style:
                                      TextStyle(fontSize: 13, color: muted))),
                          const SizedBox(width: 8),
                          Text(l.$2,
                              style: TextStyle(fontSize: 13, color: l.$3)),
                        ],
                      ),
                    ),
                  const Divider(height: 12),
                  Row(
                    children: [
                      const Expanded(
                          child: Text('Owed now',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600))),
                      Text(money(s.owed),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  for (final h in hints)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lightbulb_outline, size: 16, color: muted),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(h,
                                  style:
                                      TextStyle(fontSize: 12, color: muted))),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.payments_outlined, size: 18),
                        label: const Text('Record a bill payment'),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddTransferScreen(
                              initialToAccountId: s.account.id,
                              initialAmount: s.hasCycle && s.dueRemaining > 0
                                  ? s.dueRemaining
                                  : s.owed,
                            ),
                          ),
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.balance, size: 18),
                        label: const Text('Match bank balance'),
                        onPressed: () =>
                            showReconcileDialog(context, s.account),
                      ),
                      if (s.openingOwed > 0)
                        TextButton.icon(
                          icon: const Icon(Icons.tune, size: 18),
                          label: const Text('Fix starting amount'),
                          onPressed: () =>
                              showCardSetupDialog(context, card: s.account),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "Is 'CRED ₹8,015 on 6 Nov' this bill's payment?" — an expense that looks
/// like the card bill was paid but saved as spending. One tap makes it a
/// payment into the card: the bill clears, and it stops counting as spending.
class _PaymentGuess extends StatelessWidget {
  final Expense expense;
  final Account card;
  const _PaymentGuess({required this.expense, required this.card});

  Future<void> _confirm(BuildContext context) async {
    final expenses = context.read<ExpenseProvider>();
    final accounts = context.read<AccountProvider>();
    await expenses.updateExpense(Expense(
      id: expense.id,
      description: expense.description,
      amount: expense.amount,
      date: expense.date,
      category: 'Transfer',
      paymentMode: expense.paymentMode,
      type: DbConstants.txTransfer,
      accountId: expense.accountId,
      toAccountId: card.id,
      sourceRef: expense.sourceRef,
      note: expense.note,
      attachment: expense.attachment,
    ));
    await accounts.refreshBalances();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recorded as a payment to ${card.name}')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final from = context.read<AccountProvider>().accountById(expense.accountId);
    final symbol = from?.symbol ?? card.symbol;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Is "${expense.description}" '
            '${formatMoneyIn(symbol, expense.amount)} on '
            '${formatCompactDate(expense.date)}'
            '${from == null ? '' : ' from ${from.name}'} this bill\'s '
            'payment? It is saved as spending, so the bill still shows due.',
            style: TextStyle(fontSize: 13, color: scheme.onTertiaryContainer),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _confirm(context),
              child: const Text('Yes, it\'s the payment'),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Buy today, pay by 25 Dec · 48 days interest-free", as a tinted pill so
/// it reads at a glance.
class _BuyTodayPill extends StatelessWidget {
  final DateTime due;
  final int days;
  const _BuyTodayPill({required this.due, required this.days});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSecondaryContainer;
    return Semantics(
      label: 'Buy today, pay by ${formatCompactDate(due)}, '
          '$days days interest-free',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.shopping_bag_outlined, size: 18, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(fontSize: 14, color: fg),
                  children: [
                    const TextSpan(text: 'Buy today, pay by '),
                    TextSpan(
                        text: formatCompactDate(due),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const TextSpan(text: ' · '),
                    TextSpan(
                        text: '$days days',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const TextSpan(text: ' interest-free'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "★ 12,450 points ≈ ₹3,112 · ~320 earned since 1 Nov".
class _RewardsLine extends StatelessWidget {
  final RewardEstimate estimate;
  final String symbol;
  const _RewardsLine({required this.estimate, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final e = estimate;
    final muted = mutedTextColor(context);
    final pts = formatCount(e.points);
    final parts = [
      e.earnedOnly
          ? '~$pts points earned this period'
          : '${e.earned > 0 ? '~' : ''}$pts points',
      if (e.value != null) '≈ ${formatMoneyIn(symbol, e.value!)}',
      if (!e.earnedOnly && e.earned > 0)
        '+${formatCount(e.earned)} est. since ${formatCompactDate(e.since!)}',
      if (e.fromSms) 'balance from bank SMS',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.stars_outlined, size: 15, color: muted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(parts.join(' · '),
                style: TextStyle(fontSize: 12, color: muted)),
          ),
        ],
      ),
    );
  }
}

/// The app's available limit against the one the bank quoted in the card's
/// last SMS alert: a tick when they agree, else both figures and a way to
/// make the app match.
class _BankCheckLine extends StatelessWidget {
  final BankLimitCheck check;
  const _BankCheckLine({required this.check});

  @override
  Widget build(BuildContext context) {
    final symbol = check.card.symbol;
    final when = formatCompactDate(check.readingAt);
    if (check.matches) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Icon(Icons.verified_outlined,
                size: 14, color: incomeColor(context)),
            const SizedBox(width: 4),
            Expanded(
              child: Text('Matches the bank\'s SMS of $when',
                  style: TextStyle(fontSize: 12, color: incomeColor(context))),
            ),
          ],
        ),
      );
    }
    final warn = warningColor(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 2),
      decoration: BoxDecoration(
        border: Border.all(color: warn.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.sms_outlined, size: 16, color: warn),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Bank says ${formatMoneyIn(symbol, check.bankAvailable)} '
                  'available (SMS of $when); the app shows '
                  '${formatMoneyIn(symbol, check.appAvailable)}. '
                  '${check.difference > 0 ? 'A purchase may be missing' : 'A payment or refund may be missing'}'
                  ', or the starting amount is off.',
                  style: TextStyle(fontSize: 12, color: warn),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.balance, size: 18),
              label: const Text('Match bank'),
              onPressed: () => showReconcileDialog(context, check.card,
                  figure: ReconcileFigure.available,
                  initialAmount: check.bankAvailable),
            ),
          ),
        ],
      ),
    );
  }
}

/// A card's extra actions: add or link a second card on its limit, or take
/// it off a shared limit.
class _CardMenu extends StatelessWidget {
  final CreditCardSummary summary;
  const _CardMenu({required this.summary});

  @override
  Widget build(BuildContext context) {
    final card = summary.account;
    return PopupMenuButton<String>(
      tooltip: 'More for ${card.name}',
      onSelected: (v) async {
        final provider = context.read<AccountProvider>();
        switch (v) {
          case 'add':
            await showCardSetupDialog(context, linkTo: card);
          case 'link':
            await showCardSetupDialog(context, card: card, startShared: true);
          case 'spend':
            await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AddExpenseScreen(initialAccountId: card.id)),
            );
          case 'emi':
            await showEmiDialog(context, card);
          case 'match':
            await showReconcileDialog(context, card);
          case 'unlink':
            // Off the shared limit: the card keeps a copy of the limit.
            if (card.sharedLimitWith != null) {
              await provider.updateAccount(card.copyWith(
                  clearSharedLimitWith: true, creditLimit: summary.limit));
            } else {
              // The holder leaving hands the limit to the other card(s); it
              // keeps its own limit.
              final other = summary.sharesLimitWith.first;
              await provider.updateAccount(other.copyWith(
                  clearSharedLimitWith: true, creditLimit: summary.limit));
              for (final o in summary.sharesLimitWith.skip(1)) {
                await provider
                    .updateAccount(o.copyWith(sharedLimitWith: other.id));
              }
            }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'spend',
          child: ListTile(
            leading: Icon(Icons.add_shopping_cart),
            title: Text('Add a spend on this card'),
            subtitle: Text('One the SMS alerts missed'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'add',
          child: ListTile(
            leading: Icon(Icons.add_card),
            title: Text('Add a card on this limit'),
            subtitle: Text('e.g. the RuPay card that came with it'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'emi',
          child: ListTile(
            leading: Icon(Icons.calendar_view_month),
            title: Text('Convert a purchase to EMI'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'match',
          child: ListTile(
            leading: Icon(Icons.balance),
            title: Text('Match bank balance'),
            subtitle: Text('Outstanding or available limit'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (!summary.isSharedLimit)
          const PopupMenuItem(
            value: 'link',
            child: ListTile(
              leading: Icon(Icons.link),
              title: Text('Share limit with a card I have added'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (summary.isSharedLimit)
          const PopupMenuItem(
            value: 'unlink',
            child: ListTile(
              leading: Icon(Icons.link_off),
              title: Text('Stop sharing the limit'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }
}

/// How much of the card's credit limit is in use: a bar coloured by how
/// heavily (under 30%, up to 80%, beyond), with the share and what is left.
class _UsageBar extends StatelessWidget {
  final CreditCardSummary summary;
  const _UsageBar({required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final symbol = s.account.symbol;
    final usage = s.usage!;
    final color = switch (s.usageLevel!) {
      CreditUsageLevel.low => Theme.of(context).colorScheme.primary,
      CreditUsageLevel.moderate => warningColor(context),
      CreditUsageLevel.high => dangerColor(context),
    };
    final over = s.limitUsed - s.limit!;
    final limitText = formatMoneyIn(symbol, s.limit!);
    final caption = over > 0
        ? 'Over the $limitText limit by ${formatMoneyIn(symbol, over)}'
        : '${(usage * 100).round()}% of $limitText '
            'used · ${formatMoneyIn(symbol, s.available!)} left';
    final low = s.usageLevel == CreditUsageLevel.low;

    return Semantics(
      label: 'Credit limit usage',
      value: caption,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: usage.clamp(0.0, 1.0),
                minHeight: 6,
                color: color,
                backgroundColor: color.withValues(alpha: 0.18),
              ),
            ),
            const SizedBox(height: 3),
            ExcludeSemantics(
              child: Text(caption,
                  style: TextStyle(
                      fontSize: 12,
                      color: low ? mutedTextColor(context) : color,
                      fontWeight: low ? FontWeight.normal : FontWeight.w600)),
            ),
            if (s.emiBlocked > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                    'Includes ${formatMoneyIn(symbol, s.emiBlocked)} held '
                    'for EMIs',
                    style: TextStyle(
                        fontSize: 12, color: mutedTextColor(context))),
              ),
          ],
        ),
      ),
    );
  }
}
