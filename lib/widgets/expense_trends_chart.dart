import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../providers/expense_provider.dart';

class ExpenseTrendsChart extends StatelessWidget {
  final ExpenseProvider provider;
  const ExpenseTrendsChart({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final data = <FlSpot>[];
    for (int i = 11; i >= 0; i--) {
      final date = DateTime(now.year, now.month - i, 1);
      final total = provider.totalForMonth(date.year, date.month);
      data.add(FlSpot((11 - i).toDouble(), total / 100));
    }
    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: false),
          titlesData: FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: data,
              isCurved: true,
              color: Colors.blue,
              barWidth: 3,
              belowBarData: BarAreaData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}
