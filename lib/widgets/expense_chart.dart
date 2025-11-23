import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/expense.dart';

class ExpenseChart extends StatelessWidget {
  final List<Expense> expenses;
  const ExpenseChart({super.key, required this.expenses});

  @override
  Widget build(BuildContext context) {
    final data = _aggregateByCategory(expenses);
    final sections = data.entries
        .map((e) => PieChartSectionData(
              value: e.value,
              title: e.key,
              color: _getColorForCategory(e.key),
              radius: 60,
              titleStyle: const TextStyle(fontSize: 12, color: Colors.white),
            ))
        .toList();
    return PieChart(
      PieChartData(
        sections: sections,
        centerSpaceRadius: 40,
        sectionsSpace: 2,
      ),
    );
  }

  Map<String, double> _aggregateByCategory(List<Expense> expenses) {
    final map = <String, double>{};
    for (final e in expenses) {
      map[e.category] = (map[e.category] ?? 0) + e.amount;
    }
    return map;
  }

  Color _getColorForCategory(String category) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal
    ];
    return colors[category.hashCode % colors.length];
  }
}
