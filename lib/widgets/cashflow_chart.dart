import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../providers/expense_provider.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';

/// Grouped bars of income vs expense per month for the trailing 12 months.
class CashflowChart extends StatelessWidget {
  final ExpenseProvider provider;
  const CashflowChart({super.key, required this.provider});

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
    var maxValue = 0.0;

    for (int i = 11; i >= 0; i--) {
      final date = DateTime(now.year, now.month - i, 1);
      months.add(date);
      final income = provider.incomeForMonth(date.year, date.month) / 100;
      final expense = provider.totalForMonth(date.year, date.month) / 100;
      maxValue = max(maxValue, max(income, expense));
      groups.add(BarChartGroupData(
        x: 11 - i,
        barRods: [
          BarChartRodData(
            toY: income,
            color: incomeColor(context),
            width: 6,
            borderRadius: BorderRadius.circular(2),
          ),
          BarChartRodData(
            toY: expense,
            color: expenseColor(context),
            width: 6,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      ));
    }

    if (maxValue == 0) {
      return SizedBox(
        height: 220,
        child:
            Center(child: const Text('No transactions in the last 12 months.')),
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
      label: 'Income versus expenses over the last 12 months. $summary',
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
                      return Text(
                        _monthLabels[months[index].month - 1],
                        style: TextStyle(
                            fontSize: 10,
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
                      const TextStyle(color: Colors.white, fontSize: 12),
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
