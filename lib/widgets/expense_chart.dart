import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../utils/category_colors.dart';
import '../utils/currency_format.dart';

/// Pie breakdown of spending by category.
///
/// Takes pre-computed [totals] (category to base-currency minor units) rather
/// than a list of transactions: amounts are stored in their source account's
/// currency, so aggregating them here would have counted a $100 expense as
/// ₹100. `ExpenseProvider.categoryTotalsForMonth`/`ForYear` already do the
/// conversion, so the callers pass those straight through.
class ExpenseChart extends StatelessWidget {
  final Map<String, int> totals;
  const ExpenseChart({super.key, required this.totals});

  @override
  Widget build(BuildContext context) {
    final sections = totals.entries
        .map((e) => PieChartSectionData(
              value: e.value.toDouble(),
              title: e.key,
              color: CategoryColors.forCategory(e.key),
              radius: 60,
              titleStyle: const TextStyle(fontSize: 12, color: Colors.white),
            ))
        .toList();
    final summary = totals.entries
        .map((e) => '${e.key} ${formatMoney(e.value)}')
        .join(', ');
    return Semantics(
      label: 'Expense breakdown by category: $summary',
      child: ExcludeSemantics(
        child: PieChart(
          PieChartData(
            sections: sections,
            centerSpaceRadius: 40,
            sectionsSpace: 2,
          ),
        ),
      ),
    );
  }
}
