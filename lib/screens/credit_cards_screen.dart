import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/investment_provider.dart';
import '../utils/app_colors.dart';
import '../utils/card_period.dart';
import '../utils/credit_card_summary.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/insets.dart';
import '../widgets/card_setup_dialog.dart';
import '../widgets/empty_state.dart';
import 'account_detail_screen.dart';

/// Every credit card in one place: what went on each over a period you pick,
/// what is owed now, how much of the limit is used, and where the bill
/// stands. Opened from the dashboard's Cards shortcut.
///
/// Set a card up once — limit, statement and due days, last four digits,
/// what was owed when you started — and it is tracked from then on by the
/// transactions recorded against it: SMS alerts, entries added by hand, and
/// bill payments.
class CreditCardsScreen extends StatefulWidget {
  /// Stands in for the clock in tests.
  final DateTime? now;
  const CreditCardsScreen({super.key, this.now});

  @override
  State<CreditCardsScreen> createState() => _CreditCardsScreenState();
}

class _CreditCardsScreenState extends State<CreditCardsScreen> {
  CardPeriodKind _kind = CardPeriodKind.cycle;
  DateTime? _customStart;
  DateTime? _customEnd;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Fresh balances and card details, as the Accounts and Investments
      // screens load theirs on opening.
      context.read<AccountProvider>().fetchAccounts();
      context.read<InvestmentProvider>().fetchInvestments();
      // A cycle, or last month, can reach back into the previous year.
      _ensureLoaded(_now.year - 1, _now.year);
    });
  }

  Future<void> _ensureLoaded(int fromYear, int toYear) async {
    if (!mounted) return;
    await context
        .read<ExpenseProvider>()
        .ensureYearsLoaded([for (var y = fromYear; y <= toYear; y++) y]);
  }

  Future<void> _pickRange() async {
    final today = DateTime(_now.year, _now.month, _now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDateRange: _customStart == null
          ? DateTimeRange(
              start: DateTime(today.year, today.month, 1), end: today)
          : DateTimeRange(start: _customStart!, end: _customEnd!),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _kind = CardPeriodKind.custom;
      _customStart = picked.start;
      _customEnd = picked.end;
    });
    await _ensureLoaded(picked.start.year, picked.end.year);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountProvider>();
    final expenses = context.watch<ExpenseProvider>();
    final investments = context.watch<InvestmentProvider>();
    final now = _now;

    int spendIn(int id, DateTime from, DateTime to) =>
        expenses.spendOnAccountInRange(id, from, to) +
        investments.chargedToAccountInRange(id, from, to);

    final summaries = creditCardSummaries(
      accounts: accounts.accounts,
      now: now,
      spendInRange: spendIn,
      paidInRange: expenses.paidToAccountInRange,
      balanceOf: accounts.balanceOf,
    );
    final rows = [
      for (final s in summaries)
        () {
          final range = cardRange(s.account, _kind, now,
              customStart: _customStart, customEnd: _customEnd);
          return _CardFigures(
            summary: s,
            range: range,
            spent: spendIn(s.account.id!, range.start, range.endExclusive),
            paidIn: expenses.paidToAccountInRange(
                s.account.id!, range.start, range.endExclusive),
          );
        }(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Credit cards'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_card),
            tooltip: 'Add a credit card',
            onPressed: () => showCardSetupDialog(context),
          ),
        ],
      ),
      body: rows.isEmpty
          ? EmptyState(
              icon: Icons.credit_card,
              title: 'No credit cards yet',
              message: 'Add a card with its limit and billing days, and its '
                  'spending is tracked from SMS alerts and the expenses you '
                  'add with it.',
              actionLabel: 'Add a credit card',
              onAction: () => showCardSetupDialog(context),
            )
          : ListView(
              padding: scrollPadding(context, all: 12),
              children: [
                _PeriodFilter(
                  kind: _kind,
                  customLabel: _kind == CardPeriodKind.custom
                      ? rows.first.range.label
                      : null,
                  onSelected: (k) {
                    setState(() => _kind = k);
                  },
                  onCustom: _pickRange,
                ),
                const SizedBox(height: 8),
                _Totals(rows: rows),
                for (final r in rows) _CardTile(figures: r),
                const _HowItWorks(),
              ],
            ),
    );
  }
}

/// One card's figures for the chosen period, next to its standing ones.
class _CardFigures {
  final CreditCardSummary summary;
  final CardRange range;

  /// Charged to the card in [range], refunds taken off.
  final int spent;

  /// Paid into the card in [range]: bill payments, refunds, cashback.
  final int paidIn;
  const _CardFigures({
    required this.summary,
    required this.range,
    required this.spent,
    required this.paidIn,
  });
}

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
    final available = limited.fold<int>(0, (s, r) => s + r.summary.available!);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
                child: _Figure(
                    label: 'Spent', value: formatMoneyIn(symbol, spent))),
            Expanded(
                child: _Figure(
                    label: 'Owed now',
                    value: formatMoneyIn(symbol, owed),
                    color: expenseColor(context))),
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
            style: TextStyle(fontSize: 12, color: mutedTextColor(context))),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold, color: color)),
        ),
      ],
    );
  }
}

class _CardTile extends StatelessWidget {
  final _CardFigures figures;
  const _CardTile({required this.figures});

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
    final bill = _billStatus(context);
    // What this card still needs before it can be tracked fully.
    final missing = [
      if (s.limit == null) 'credit limit',
      if (!s.hasCycle) 'statement & due days',
      if (account.last4 == null) 'last 4 digits',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
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
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.tune),
                    tooltip: 'Set up ${account.name}',
                    onPressed: () =>
                        showCardSetupDialog(context, card: account),
                  ),
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
                    if (s.limit != null) _UsageBar(summary: s),
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
                    if (missing.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: ActionChip(
                          avatar: const Icon(Icons.add, size: 18),
                          label: Text('Add ${missing.join(', ')}',
                              overflow: TextOverflow.ellipsis),
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
      ),
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
    final over = s.owed - s.limit!;
    final caption = over > 0
        ? 'Over the ${formatMoneyIn(symbol, s.limit!)} limit by '
            '${formatMoneyIn(symbol, over)}'
        : '${(usage * 100).round()}% of ${formatMoneyIn(symbol, s.limit!)} '
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
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Spending is tracked automatically from the SMS alerts filed '
              'against a card (its last 4 digits route them) and the expenses '
              'you add with it. Bill payments recorded as a transfer to the '
              'card bring "owed" down. Tap a card for its statement by cycle.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
        ],
      ),
    );
  }
}
