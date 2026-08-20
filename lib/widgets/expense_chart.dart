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
///
/// When [onCategoryTap] is given, tapping a slice highlights it and reports the
/// category, so the caller can show that category's transactions.
class ExpenseChart extends StatefulWidget {
  final Map<String, int> totals;
  final ValueChanged<String>? onCategoryTap;
  const ExpenseChart({super.key, required this.totals, this.onCategoryTap});

  @override
  State<ExpenseChart> createState() => _ExpenseChartState();
}

class _ExpenseChartState extends State<ExpenseChart> {
  /// The slice currently under the finger, drawn slightly larger. -1 = none.
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final entries = widget.totals.entries.toList();
    final sections = [
      for (var i = 0; i < entries.length; i++)
        PieChartSectionData(
          value: entries[i].value.toDouble(),
          title: entries[i].key,
          color: CategoryColors.forCategory(entries[i].key),
          radius: i == _touchedIndex ? 70 : 60,
          titleStyle: TextStyle(
            fontSize: i == _touchedIndex ? 13 : 12,
            color: Colors.white,
            fontWeight:
                i == _touchedIndex ? FontWeight.bold : FontWeight.normal,
          ),
        ),
    ];
    final tappable = widget.onCategoryTap != null;
    final summary =
        entries.map((e) => '${e.key} ${formatMoney(e.value)}').join(', ');
    return Semantics(
      label: 'Expense breakdown by category: $summary'
          '${tappable ? '. Tap a slice for its transactions.' : ''}',
      child: ExcludeSemantics(
        child: PieChart(
          PieChartData(
            sections: sections,
            centerSpaceRadius: 40,
            sectionsSpace: 2,
            pieTouchData: PieTouchData(
              enabled: tappable,
              touchCallback: (event, response) {
                if (!tappable) return;
                final idx =
                    response?.touchedSection?.touchedSectionIndex ?? -1;
                if (idx != _touchedIndex) {
                  setState(() => _touchedIndex = idx);
                }
                // Fire once, on release, over a real slice.
                if (event is FlTapUpEvent &&
                    idx >= 0 &&
                    idx < entries.length) {
                  widget.onCategoryTap!(entries[idx].key);
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
