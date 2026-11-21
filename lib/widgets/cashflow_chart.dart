import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../providers/expense_provider.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/font_sizes.dart';
import '../utils/dimens.dart';

/// Grouped bars of income vs expense per month for the trailing [months]
/// months.
class CashflowChart extends StatelessWidget {
  final ExpenseProvider provider;
  final int months;
  const CashflowChart({super.key, required this.provider, this.months = 12});

  static const _monthLabels = [
    'J',
    'F',
    'M',
    'A',
    'M',
    'J',
    'J',
    'A',
    'S',
    'O',
    'N',
    'D'
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final groups = <BarChartGroupData>[];
    final months = <DateTime>[];
    final last = this.months - 1;
    // Thinner bars, and every other label, once there are more months.
    final barWidth = this.months > 12 ? 3.0 : 6.0;
    var maxValue = 0.0;

    for (int i = last; i >= 0; i--) {
      final date = DateTime(now.year, now.month - i, 1);
      months.add(date);
      final income = provider.incomeForMonth(date.year, date.month) / 100;
      final expense = provider.totalForMonth(date.year, date.month) / 100;
      maxValue = max(maxValue, max(income, expense));
      groups.add(BarChartGroupData(
        x: last - i,
        barRods: [
          BarChartRodData(
            toY: income,
            color: incomeColor(context),
            width: barWidth,
            borderRadius: BorderRadius.circular(Radii.xs),
          ),
          BarChartRodData(
            toY: expense,
            color: expenseColor(context),
            width: barWidth,
            borderRadius: BorderRadius.circular(Radii.xs),
          ),
        ],
      ));
    }

    if (maxValue == 0) {
      return SizedBox(
        height: 220,
        child:
            Center(
                child: Text('No transactions in the last ${this.months} months.')),
      );
    }

    // Spoken summary: the bars are painted on a canvas, so a screen reader
    // would otherwise find nothing here at all.
    final summary = [
      for (var i = 0; i < months.length; i++)
        '${_monthLabels[months[i].month - 1]}${months[i].year % 100}: '
            'in ${formatMoneyRounded(provider.incomeForMonth(months[i].year, months[i].month))}, '
            'out ${formatMoneyRounded(provider.totalForMonth(months[i].year, months[i].month))}'
    ].join('; ');

    return Semantics(
      label:
          'Income versus expenses over the last ${this.months} months. $summary',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              barGroups: groups,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= months.length) {
                        return const SizedBox.shrink();
                      }
                      if (this.months > 12 && (last - index).isOdd) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        _monthLabels[months[index].month - 1],
                        style: TextStyle(
                            fontSize: FontSizes.tick,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final date = months[group.x];
                    final label = rodIndex == 0 ? 'Income' : 'Expense';
                    return BarTooltipItem(
                      '${date.year}-${date.month.toString().padLeft(2, '0')}\n$label: ${formatMoneyRounded((rod.toY * 100).round())}',
                      const TextStyle(
                          color: Colors.white, fontSize: FontSizes.caption),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
