import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../providers/expense_provider.dart';
import '../utils/currency_format.dart';

/// Twelve-month spending trend.
///
/// Totals come from [ExpenseProvider], which converts foreign-currency rows to
/// the base currency, so the line agrees with the totals shown beside it.
class ExpenseTrendsChart extends StatelessWidget {
  final ExpenseProvider provider;
  const ExpenseTrendsChart({super.key, required this.provider});

  static const _monthInitials = [
    'J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D' //
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = <DateTime>[];
    final data = <FlSpot>[];
    for (int i = 11; i >= 0; i--) {
      final date = DateTime(now.year, now.month - i, 1);
      months.add(date);
      final total = provider.totalForMonth(date.year, date.month);
      data.add(FlSpot((11 - i).toDouble(), total / 100));
    }

    final scheme = Theme.of(context).colorScheme;
    final axisStyle = TextStyle(
      fontSize: 10,
      color: scheme.onSurfaceVariant,
    );

    // Spoken summary: the chart itself is a canvas, so without this a screen
    // reader announces nothing at all where the trend is.
    final summary = [
      for (var i = 0; i < months.length; i++)
        '${_monthInitials[months[i].month - 1]}'
            '${months[i].year % 100}: '
            '${formatMoney((data[i].y * 100).round())}'
    ].join(', ');

    return Semantics(
      label: 'Spending over the last 12 months. $summary',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              // Axis labels were disabled outright, so the line had no scale
              // for anyone — sighted or not.
              gridData: FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final i = value.round();
                      if (i < 0 || i >= months.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(_monthInitials[months[i].month - 1],
                            style: axisStyle),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (value, meta) => Text(
                      formatMoneyRounded((value * 100).round()),
                      style: axisStyle,
                    ),
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: data,
                  isCurved: true,
                  color: scheme.primary,
                  barWidth: 3,
                  belowBarData: BarAreaData(show: false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
