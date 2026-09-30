import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/account_provider.dart';
import '../providers/budget_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/investment_provider.dart';
import '../providers/recurring_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/add_transfer_screen.dart';
import '../utils/alerts.dart';
import '../utils/app_colors.dart';
import '../utils/billing_cycle.dart';
import '../utils/currency_format.dart';

/// Dashboard banner that proactively surfaces budgets nearing/over their cap
/// and recurring bills coming due, so the user is warned without needing to
/// open each screen. Renders nothing when there is nothing to flag.
class AlertsBanner extends StatelessWidget {
  const AlertsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Consumer4<SettingsProvider, BudgetProvider, ExpenseProvider,
        RecurringProvider>(
      builder: (context, settings, budgets, expenses, recurring, _) {
        if (!settings.alertsEnabled) return const SizedBox.shrink();

        final budgetIssues = budgetAlerts(
          budgets: budgets.budgets,
          year: now.year,
          month: now.month,
          spentForCategory: (c) =>
              expenses.spentForCategoryInMonth(now.year, now.month, c),
          totalSpent: () => expenses.totalForMonth(now.year, now.month),
        );
        final bills = upcomingBills(rules: recurring.rules, now: now);

        // Credit-card statements coming due (needs the accounts and their
        // per-card spend).
        final accounts = context.watch<AccountProvider>();
        final investments = context.watch<InvestmentProvider>();
        final cardDue = creditCardReminders(
          accounts: accounts.accounts,
          now: now,
          // Investments bought on the card are on its statement too.
          spendInRange: (id, from, to) =>
              expenses.spendOnAccountInRange(id, from, to) +
              investments.chargedToAccountInRange(id, from, to,
                  rate: accounts.accountById(id)?.rate ?? 1.0),
          paidInRange: expenses.paidToAccountInRange,
        );

        if (budgetIssues.isEmpty && bills.isEmpty && cardDue.isEmpty) {
          return const SizedBox.shrink();
        }

        final warn = warningColor(context);
        final tiles = <Widget>[
          for (final a in budgetIssues) _budgetTile(context, a),
          for (final r in cardDue) _cardTile(context, r),
          for (final b in bills) _billTile(context, b),
        ];

        final dark = Theme.of(context).brightness == Brightness.dark;
        return Card(
          elevation: 0,
          color: warn.withValues(alpha: dark ? 0.16 : 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: warn.withValues(alpha: 0.45)),
          ),
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.notifications_active, size: 18, color: warn),
                    const SizedBox(width: 8),
                    Text('Alerts',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                ...tiles,
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _budgetTile(BuildContext context, BudgetAlert a) {
    final over = a.isOver;
    final pct = (a.ratio * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(over ? Icons.error : Icons.warning_amber,
              size: 16,
              color: over ? dangerColor(context) : warningColor(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              over
                  ? '${a.category}: over budget by ${formatMoney(a.spent - a.budget)}'
                  : '${a.category}: $pct% of budget used',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardTile(BuildContext context, CreditCardReminder r) {
    String whenLabel;
    if (r.isOverdue) {
      whenLabel = 'overdue';
    } else if (r.isToday) {
      whenLabel = 'by today';
    } else if (r.daysUntilDue == 1) {
      whenLabel = 'by tomorrow';
    } else {
      whenLabel = 'within ${r.daysUntilDue} days';
    }
    // What was spent since the statement is on the next bill, not this one;
    // shown so the card's running total is visible alongside what's due.
    final spentNote = r.currentCycleSpend > 0
        ? ' · ${formatMoneyIn(r.symbol, r.currentCycleSpend)} spent since '
            'the statement'
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.credit_card,
              size: 16,
              color: r.isOverdue ? dangerColor(context) : infoColor(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${r.accountName}: pay ${formatMoneyIn(r.symbol, r.amountDue)} '
              '$whenLabel$spentNote',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          // Records the payment as a transfer into the card, which is what
          // clears this reminder; opened with the card and amount filled in.
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddTransferScreen(
                  initialToAccountId: r.accountId,
                  initialAmount: r.amountDue,
                ),
              ),
            ),
            child: const Text('Pay'),
          ),
        ],
      ),
    );
  }

  Widget _billTile(BuildContext context, BillAlert b) {
    String whenLabel;
    if (b.isOverdue) {
      whenLabel = 'overdue';
    } else if (b.isToday) {
      whenLabel = 'due today';
    } else if (b.daysUntil == 1) {
      whenLabel = 'due tomorrow';
    } else {
      whenLabel = 'due in ${b.daysUntil} days';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.event, size: 16, color: infoColor(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${b.description} ${formatMoney(b.amount)} — $whenLabel',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
