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
              // Dragging along the line shows the exact figure at each month.
              // Without this the framework default renders a bare decimal
              // (e.g. "1234.0") with weak contrast, so per-point values were
              // hard to read.
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => scheme.inverseSurface,
                  tooltipRoundedRadius: 8,
                  getTooltipItems: (touchedSpots) => [
                    for (final s in touchedSpots)
                      LineTooltipItem(
                        (s.x.round() >= 0 && s.x.round() < months.length
                                ? '${_monthInitials[months[s.x.round()].month - 1]}'
                                    '${months[s.x.round()].year % 100}\n'
                                : '') +
                            formatMoney((s.y * 100).round()),
                        TextStyle(
                          color: scheme.onInverseSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
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
                  // A dot at each month makes the individual data points
                  // visible and easy to target when reading their values.
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, bar, index) =>
                        FlDotCirclePainter(
                      radius: 3,
                      color: scheme.primary,
                      strokeWidth: 0,
                      strokeColor: Colors.transparent,
                    ),
                  ),
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
