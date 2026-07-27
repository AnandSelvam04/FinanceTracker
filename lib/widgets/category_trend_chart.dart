import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../providers/expense_provider.dart';
import '../utils/category_colors.dart';
import '../utils/currency_format.dart';

/// One line per selected category over the trailing 12 months.
class CategoryTrendChart extends StatelessWidget {
  final ExpenseProvider provider;
  final List<String> categories;
  const CategoryTrendChart({
    super.key,
    required this.provider,
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = <DateTime>[
      for (int i = 11; i >= 0; i--) DateTime(now.year, now.month - i, 1),
    ];

    if (categories.isEmpty) {
      return SizedBox(
        height: 220,
        child: Center(child: const Text('Select categories to compare.')),
      );
    }

    final bars = <LineChartBarData>[];
    for (final category in categories) {
      final spots = <FlSpot>[];
      for (var i = 0; i < months.length; i++) {
        final month = months[i];
        final total = provider.categoryTotalsForMonth(
                month.year, month.month)[category] ??
            0;
        spots.add(FlSpot(i.toDouble(), total / 100));
      }
      bars.add(LineChartBarData(
        spots: spots,
        isCurved: true,
        color: CategoryColors.forCategory(category),
        barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
    }

    // Spoken summary: the lines are painted on a canvas, so a screen reader
    // would otherwise find nothing here at all. One sentence per category,
    // rather than 12 numbers each, to keep it listenable.
    final summary = [
      for (final category in categories)
        '$category: ${[
          for (final m in months)
            formatMoneyRounded(
                provider.categoryTotalsForMonth(m.year, m.month)[category] ?? 0)
        ].join(', ')}'
    ].join('. ');

    return Semantics(
      label: 'Monthly spend by category over the last 12 months. $summary',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
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
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= months.length) {
                        return const SizedBox.shrink();
                      }
                      // Label every other month to avoid crowding.
                      if (index % 2 != 0) return const SizedBox.shrink();
                      return Text('${months[index].month}',
                          style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant));
                    },
                  ),
                ),
              ),
              lineBarsData: bars,
            ),
          ),
        ),
      ),
    );
  }
}
