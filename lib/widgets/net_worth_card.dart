import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/net_worth_point.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/investment_provider.dart';
import '../services/db_service.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';

/// Dashboard card showing current net worth (liquid account balances plus
/// recorded investments) and a 12-month month-end trend line.
class NetWorthCard extends StatelessWidget {
  const NetWorthCard({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuild whenever balances, investments, or transactions change so the
    // headline figure and trend stay in sync with the rest of the dashboard.
    return Consumer3<AccountProvider, InvestmentProvider, ExpenseProvider>(
      builder: (context, accounts, investments, expenses, _) {
        // Convert each account to the base currency so mixed-currency
        // holdings roll up to a single, meaningful net-worth figure.
        final liquid = accounts.totalBaseBalance();
        final invested =
            investments.investments.fold<int>(0, (sum, i) => sum + i.amount);
        final netWorth = liquid + invested;

        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.account_balance, size: 20),
                    const SizedBox(width: 8),
                    Text('Net Worth',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(
                      formatMoneySigned(netWorth),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: netWorth < 0
                            ? Colors.red.shade400
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Accounts ${formatMoneySigned(liquid)} · '
                  'Investments ${formatMoneySigned(invested)}',
                  style:
                      TextStyle(fontSize: 12, color: mutedTextColor(context)),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 120,
                  // key forces the FutureBuilder to refetch when totals change.
                  child: _NetWorthTrend(
                    key:
                        ValueKey('$netWorth-${investments.investments.length}'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NetWorthTrend extends StatelessWidget {
  const _NetWorthTrend({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<NetWorthPoint>>(
      future: DBService().netWorthSeries(12),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // A static placeholder (not a spinner) keeps widget tests that call
          // pumpAndSettle from hanging on an indefinite animation.
          return const SizedBox.shrink();
        }
        final series = snapshot.data!;
        if (series.every((p) => p.value == 0)) {
          return Center(
            child: Text('No history yet',
                style: TextStyle(fontSize: 12, color: mutedTextColor(context))),
          );
        }
        final spots = <FlSpot>[
          for (int i = 0; i < series.length; i++)
            FlSpot(i.toDouble(), series[i].value / 100),
        ];
        final color = Theme.of(context).colorScheme.primary;
        return Semantics(
          label: 'Net worth trend over the last 12 months',
          child: LineChart(
            LineChartData(
              gridData: FlGridData(show: false),
              titlesData: FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: color,
                  barWidth: 3,
                  dotData: FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: color.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
