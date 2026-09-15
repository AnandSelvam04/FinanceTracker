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
import '../utils/date_format.dart';
import 'animated_money.dart';

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
        final onGradient = onBrandGradient(context);
        final subtle = onGradient.withValues(alpha: 0.82);

        return Card(
          // The gradient supplies the fill, so drop the card's own surface color
          // and border and let the container paint edge to edge.
          margin: const EdgeInsets.symmetric(vertical: 6),
          clipBehavior: Clip.antiAlias,
          color: Colors.transparent,
          // A soft, brand-tinted elevation shadow lifts the hero card off the
          // dashboard surface so it reads as the primary focal point, rather
          // than sitting flush like the plainer cards below it. The shadow is
          // cast by the card's Material (outside the clipped fill), so it is
          // not swallowed by clipBehavior the way an inner BoxShadow would be.
          elevation: 8,
          shadowColor: Theme.of(context)
              .colorScheme
              .primary
              .withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: brandGradient(context),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.account_balance, size: 20, color: onGradient),
                    const SizedBox(width: 8),
                    Text('Net Worth',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: onGradient)),
                    const Spacer(),
                    AnimatedMoney(
                      value: netWorth,
                      format: formatMoneySigned,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: onGradient,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Accounts ${formatMoneySigned(liquid)} · '
                  'Investments ${formatMoneySigned(invested)}',
                  style: TextStyle(fontSize: 12, color: subtle),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 120,
                  // key forces the FutureBuilder to refetch when totals change.
                  child: _NetWorthTrend(
                    lineColor: onGradient,
                    mutedColor: subtle,
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
  /// Colors are passed in so the trend line reads clearly on the card's
  /// gradient fill instead of using the scheme's primary (which the gradient
  /// is built from and would blend into).
  final Color lineColor;
  final Color mutedColor;
  const _NetWorthTrend({
    super.key,
    required this.lineColor,
    required this.mutedColor,
  });

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
                style: TextStyle(fontSize: 12, color: mutedColor)),
          );
        }
        final spots = <FlSpot>[
          for (int i = 0; i < series.length; i++)
            FlSpot(i.toDouble(), series[i].value / 100),
        ];
        final color = lineColor;
        final lastX = spots.last.x;
        return Semantics(
          label: 'Net worth trend over the last 12 months',
          child: LineChart(
            LineChartData(
              gridData: FlGridData(show: false),
              titlesData: FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              // Tap or drag along the line to read the exact month-end figure,
              // so the trend is inspectable instead of purely decorative.
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => Colors.black.withValues(alpha: 0.75),
                  getTooltipItems: (touchedSpots) => [
                    for (final s in touchedSpots)
                      LineTooltipItem(
                        (s.x.round() >= 0 && s.x.round() < series.length
                                ? '${monthName(series[s.x.round()].month.month).substring(0, 3)} '
                                    '${series[s.x.round()].month.year % 100}\n'
                                : '') +
                            formatMoney((s.y * 100).round()),
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: color,
                  barWidth: 3,
                  // Mark only the latest point, so the current net worth reads
                  // as the endpoint of the trend at a glance.
                  dotData: FlDotData(
                    show: true,
                    checkToShowDot: (spot, _) => spot.x == lastX,
                    getDotPainter: (spot, percent, bar, index) =>
                        FlDotCirclePainter(
                      radius: 3.5,
                      color: color,
                      strokeWidth: 0,
                    ),
                  ),
                  // A soft top-down gradient fill gives the sparkline more
                  // presence on the hero card than a flat tint.
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        color.withValues(alpha: 0.28),
                        color.withValues(alpha: 0.02),
                      ],
                    ),
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
