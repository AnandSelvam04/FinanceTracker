import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/investment_provider.dart';
import '../screens/account_detail_screen.dart';
import '../utils/app_colors.dart';
import '../utils/credit_card_summary.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import 'section_header.dart';

/// The dashboard's Credit cards section: for every credit-card account, what
/// has gone on it since the last statement, what is owed, and where the last
/// bill stands — always visible, not only in the week a bill falls due.
/// Hidden when there are no credit-card accounts.
class CreditCardsCard extends StatelessWidget {
  /// Stands in for the clock in tests.
  final DateTime? now;
  const CreditCardsCard({super.key, this.now});

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountProvider>();
    final expenses = context.watch<ExpenseProvider>();
    final investments = context.watch<InvestmentProvider>();
    final cards = creditCardSummaries(
      accounts: accounts.accounts,
      now: now ?? DateTime.now(),
      // Investments bought on the card are on its bill too, as in the due
      // reminders.
      spendInRange: (id, from, to) =>
          expenses.spendOnAccountInRange(id, from, to) +
          investments.chargedToAccountInRange(id, from, to),
      paidInRange: expenses.paidToAccountInRange,
      balanceOf: accounts.balanceOf,
    );
    if (cards.isEmpty) return const SizedBox.shrink();

    // A combined figure only makes sense when every card is in one currency.
    final symbols = {for (final c in cards) c.account.symbol};
    final symbol = symbols.length == 1 ? symbols.single : null;
    final muted = mutedTextColor(context);

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Credit cards'),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                if (symbol != null && cards.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: _Figure(
                            label: 'Spent this cycle',
                            value: formatMoneyIn(symbol,
                                cards.fold(0, (s, c) => s + c.cycleSpend)),
                          ),
                        ),
                        Expanded(
                          child: _Figure(
                            label: 'Owed in total',
                            value: formatMoneyIn(
                                symbol, cards.fold(0, (s, c) => s + c.owed)),
                            color: expenseColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0 || (symbol != null && cards.length > 1))
                    const Divider(height: 1),
                  _CardRow(summary: cards[i], muted: muted),
                ],
              ],
            ),
          ),
        ],
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
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ),
      ],
    );
  }
}

class _CardRow extends StatelessWidget {
  final CreditCardSummary summary;
  final Color muted;
  const _CardRow({required this.summary, required this.muted});

  /// Where the last bill stands, and how urgent it is.
  (String, Color?) _status(BuildContext context) {
    final s = summary;
    final symbol = s.account.symbol;
    if (!s.hasCycle) {
      return ('Add statement & due days to track bills', null);
    }
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
        '$amount due ${formatShortDate(cycle.dueDate)} · '
            'in $days day${days == 1 ? '' : 's'}',
        days <= 7 ? warningColor(context) : null
      );
    }
    final next = 'next statement ${formatShortDate(cycle.nextStatementDate)}';
    if (s.billPaid) return ('Bill paid ✓ · $next', incomeColor(context));
    return ('Nothing billed · $next', null);
  }

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final account = s.account;
    final (status, statusColor) = _status(context);
    final own = account.color == null ? null : Color(account.color!);
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: own == null
            ? scheme.secondaryContainer
            : own.withValues(alpha: dark ? 0.28 : 0.15),
        child:
            Icon(Icons.credit_card, color: own ?? scheme.onSecondaryContainer),
      ),
      title: Text(
        [account.name, if (account.last4 != null) '••${account.last4}']
            .join(' '),
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status,
              style: TextStyle(
                  fontSize: 12,
                  color: statusColor ?? muted,
                  fontWeight: statusColor == null
                      ? FontWeight.normal
                      : FontWeight.w600)),
          Text(
            s.owed > 0
                ? '${formatMoneyIn(account.symbol, s.owed)} owed'
                : s.credit > 0
                    ? '${formatMoneyIn(account.symbol, s.credit)} in credit'
                    : 'Nothing owed',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(formatMoneyIn(account.symbol, s.cycleSpend),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(s.hasCycle ? 'this cycle' : 'this month',
              style: TextStyle(fontSize: 12, color: muted)),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              AccountDetailScreen(account: account, showActions: false),
        ),
      ),
    );
  }
}
