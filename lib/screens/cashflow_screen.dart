import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../providers/investment_provider.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/insets.dart';
import '../widgets/cashflow_chart.dart';
import '../widgets/section_header.dart';
import '../utils/font_sizes.dart';
import '../utils/dimens.dart';

class CashflowScreen extends StatefulWidget {
  const CashflowScreen({super.key});

  @override
  State<CashflowScreen> createState() => _CashflowScreenState();
}

class _CashflowScreenState extends State<CashflowScreen> {
  /// How many months back the screen looks.
  int _span = 12;

  static const _spans = [6, 12, 24];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Loads every year the span reaches into.
  void _load() {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month - (_span - 1));
    unawaited(context
        .read<ExpenseProvider>()
        .ensureYearsLoaded([for (var y = first.year; y <= now.year; y++) y]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cash flow')),
      body: Consumer2<ExpenseProvider, InvestmentProvider>(
        builder: (context, provider, investments, _) {
          final now = DateTime.now();
          final months = [
            for (var i = _span - 1; i >= 0; i--)
              DateTime(now.year, now.month - i, 1),
          ];
          var totalIncome = 0;
          var totalExpense = 0;
          for (final m in months) {
            totalIncome += provider.incomeForMonth(m.year, m.month);
            totalExpense += provider.totalForMonth(m.year, m.month);
          }
          final net = totalIncome - totalExpense;
          // Money put into investments over the same window. It is not
          // spending (it stays the user's), so it is shown apart from the
          // net rather than taken off it.
          final invested = investments.investedInRange(
              months.first, DateTime(now.year, now.month + 1, 1));
          final savingsRate = totalIncome > 0 ? net * 100 / totalIncome : null;

          return SingleChildScrollView(
            padding: scrollPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      for (final s in _spans)
                        ButtonSegment(value: s, label: Text('$s months')),
                    ],
                    selected: {_span},
                    onSelectionChanged: (v) {
                      setState(() => _span = v.first);
                      _load();
                    },
                  ),
                ),
                const SizedBox(height: Space.lg),
                SectionHeader('Income vs expense (last $_span months)'),
                const SizedBox(height: Space.sm),
                CashflowChart(provider: provider, months: _span),
                const SizedBox(height: Space.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _LegendDot(color: incomeColor(context), label: 'Income'),
                    const SizedBox(width: Space.lg),
                    _LegendDot(color: expenseColor(context), label: 'Expense'),
                  ],
                ),
                const SizedBox(height: Space.lg),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(Space.lg),
                    child: Column(
                      children: [
                        _SummaryRow(
                            label: 'Total income',
                            value: totalIncome,
                            color: incomeColor(context)),
                        const SizedBox(height: Space.sm),
                        _SummaryRow(
                            label: 'Total expense',
                            value: totalExpense,
                            color: expenseColor(context)),
                        const Divider(),
                        _SummaryRow(
                            label: 'Net (saved)',
                            value: net,
                            color: net >= 0
                                ? incomeColor(context)
                                : expenseColor(context)),
                        const SizedBox(height: Space.sm),
                        _SummaryRow(
                            label: 'Invested',
                            value: invested,
                            color: Theme.of(context).colorScheme.onSurface),
                        if (savingsRate != null) ...[
                          const SizedBox(height: Space.sm),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Savings rate'),
                              Text(
                                  '${savingsRate.toStringAsFixed(0)}% of income',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: savingsRate >= 0
                                          ? incomeColor(context)
                                          : expenseColor(context))),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Space.lg),
                const SectionHeader('Month by month'),
                const SizedBox(height: Space.xs),
                // The figures behind the bars, newest first.
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Space.lg, vertical: Space.sm),
                    child: Column(
                      children: [
                        _MonthRow.header(context),
                        const Divider(height: 1),
                        for (final m in months.reversed)
                          _MonthRow(
                            label: '${monthName(m.month).substring(0, 3)} '
                                '${m.year}',
                            income: provider.incomeForMonth(m.year, m.month),
                            expense: provider.totalForMonth(m.year, m.month),
                          ),
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

/// One month's line in the month-by-month table: in, out and what was left.
class _MonthRow extends StatelessWidget {
  final String label;
  final int income;
  final int expense;
  final bool isHeader;

  const _MonthRow(
      {required this.label, required this.income, required this.expense})
      : isHeader = false;

  const _MonthRow._header()
      : label = 'Month',
        income = 0,
        expense = 0,
        isHeader = true;

  static Widget header(BuildContext context) => const _MonthRow._header();

  @override
  Widget build(BuildContext context) {
    final muted = mutedTextColor(context);
    final net = income - expense;
    Widget cell(String text, {Color? color, bool bold = false}) => Expanded(
          flex: 3,
          child: Text(text,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: FontSizes.caption,
                  color: isHeader ? muted : color,
                  fontWeight: bold ? FontWeight.w600 : null)),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label,
                style: TextStyle(
                    fontSize: FontSizes.caption,
                    color: isHeader ? muted : null)),
          ),
          cell(isHeader ? 'In' : formatMoneyRounded(income),
              color: incomeColor(context)),
          cell(isHeader ? 'Out' : formatMoneyRounded(expense),
              color: expenseColor(context)),
          cell(
              isHeader
                  ? 'Net'
                  // No sign while amounts are hidden: it gives the net away.
                  : '${net < 0 && !CurrencyFormat.hideAmounts ? '-' : ''}'
                      '${formatMoneyRounded(net.abs())}',
              color: net >= 0 ? null : expenseColor(context),
              bold: true),
        ],
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
        const SizedBox(width: Space.xs),
        Text(label, style: const TextStyle(fontSize: FontSizes.caption)),
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
