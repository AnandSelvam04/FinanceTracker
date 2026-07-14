import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/budget_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/recurring_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/alerts.dart';
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

        final categoryTotals =
            expenses.categoryTotalsForMonth(now.year, now.month);
        final budgetIssues = budgetAlerts(
          budgets: budgets.budgets,
          year: now.year,
          month: now.month,
          spentForCategory: (c) => categoryTotals[c] ?? 0,
        );
        final bills = upcomingBills(rules: recurring.rules, now: now);

        if (budgetIssues.isEmpty && bills.isEmpty) {
          return const SizedBox.shrink();
        }

        final tiles = <Widget>[
          for (final a in budgetIssues) _budgetTile(a),
          for (final b in bills) _billTile(b),
        ];

        return Card(
          elevation: 0,
          color: Colors.amber.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.amber.withValues(alpha: 0.5)),
          ),
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.notifications_active, size: 18),
                    SizedBox(width: 8),
                    Text('Alerts',
                        style: TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _budgetTile(BudgetAlert a) {
    final over = a.isOver;
    final pct = (a.ratio * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(over ? Icons.error : Icons.warning_amber,
              size: 16, color: over ? Colors.red : Colors.orange),
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

  Widget _billTile(BillAlert b) {
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
          Icon(Icons.event, size: 16, color: Colors.blue.shade600),
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
