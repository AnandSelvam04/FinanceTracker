import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/insets.dart';
import '../widgets/cashflow_chart.dart';

class CashflowScreen extends StatefulWidget {
  const CashflowScreen({super.key});

  @override
  State<CashflowScreen> createState() => _CashflowScreenState();
}

class _CashflowScreenState extends State<CashflowScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ExpenseProvider>();
      final now = DateTime.now();
      // The trailing 12-month window can span two calendar years.
      provider.ensureYearLoaded(now.year);
      provider.ensureYearLoaded(now.year - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cash Flow')),
      body: Consumer<ExpenseProvider>(
        builder: (context, provider, _) {
          final now = DateTime.now();
          var totalIncome = 0;
          var totalExpense = 0;
          for (int i = 11; i >= 0; i--) {
            final date = DateTime(now.year, now.month - i, 1);
            totalIncome += provider.incomeForMonth(date.year, date.month);
            totalExpense += provider.totalForMonth(date.year, date.month);
          }
          final net = totalIncome - totalExpense;

          return SingleChildScrollView(
            padding: scrollPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Income vs Expense (Last 12 Months)',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                CashflowChart(provider: provider),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _LegendDot(color: Colors.green.shade600, label: 'Income'),
                    const SizedBox(width: 16),
                    _LegendDot(color: Colors.red.shade400, label: 'Expense'),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _SummaryRow(
                            label: 'Total Income',
                            value: totalIncome,
                            color: incomeColor(context)),
                        const SizedBox(height: 8),
                        _SummaryRow(
                            label: 'Total Expense',
                            value: totalExpense,
                            color: expenseColor(context)),
                        const Divider(),
                        _SummaryRow(
                            label: 'Net',
                            value: net,
                            color: net >= 0
                                ? incomeColor(context)
                                : expenseColor(context)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _SummaryRow(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(formatMoneySigned(value),
            style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
