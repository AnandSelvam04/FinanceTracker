import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/expense_provider.dart';
import '../services/statement_pdf.dart';
import '../utils/category_colors.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../widgets/month_selector.dart';

class MonthlySummaryScreen extends StatefulWidget {
  const MonthlySummaryScreen({super.key});

  @override
  State<MonthlySummaryScreen> createState() => _MonthlySummaryScreenState();
}

class _MonthlySummaryScreenState extends State<MonthlySummaryScreen> {
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLoaded());
  }

  void _ensureLoaded() {
    final provider = context.read<ExpenseProvider>();
    provider.ensureYearLoaded(_year);
    // Previous month may fall in the prior calendar year (Jan MoM).
    provider.ensureYearLoaded(_year - 1);
  }

  ({int year, int month}) get _previousMonth {
    if (_month == 1) return (year: _year - 1, month: 12);
    return (year: _year, month: _month - 1);
  }

  String get _periodLabel => '$_year-${_month.toString().padLeft(2, '0')}';

  Future<void> _sharePdf() async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<ExpenseProvider>();
    final transactions = provider.expensesForMonth(_year, _month);
    if (transactions.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No transactions to include.')),
      );
      return;
    }
    try {
      final file = await StatementPdf.build(
        title: 'Finance Tracker Statement',
        periodLabel: _periodLabel,
        transactions: transactions,
      );
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Statement $_periodLabel',
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Share PDF statement',
            onPressed: _sharePdf,
          ),
        ],
      ),
      body: Consumer<ExpenseProvider>(
        builder: (context, provider, _) {
          final income = provider.incomeForMonth(_year, _month);
          final expense = provider.totalForMonth(_year, _month);
          final net = income - expense;
          final savingsRate = income > 0 ? (net / income) * 100 : null;

          final prev = _previousMonth;
          final prevExpense = provider.totalForMonth(prev.year, prev.month);

          final categoryTotals = provider.categoryTotalsForMonth(_year, _month);
          final prevCategoryTotals =
              provider.categoryTotalsForMonth(prev.year, prev.month);
          final sortedCategories = categoryTotals.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final topCategories = sortedCategories.take(5).toList();

          final txCount = provider.expensesForMonth(_year, _month).length;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MonthSelector(
                  initialYear: _year,
                  initialMonth: _month,
                  onChanged: (y, m) {
                    setState(() {
                      _year = y;
                      _month = m;
                    });
                    _ensureLoaded();
                  },
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _row('Income', formatMoney(income),
                            color: incomeColor(context)),
                        const SizedBox(height: 8),
                        _row('Expense', formatMoney(expense),
                            color: expenseColor(context)),
                        const Divider(),
                        _row('Net', formatMoney(net),
                            color: net >= 0
                                ? incomeColor(context)
                                : expenseColor(context),
                            bold: true),
                        const SizedBox(height: 8),
                        _row(
                          'Savings rate',
                          savingsRate == null
                              ? '—'
                              : '${savingsRate.toStringAsFixed(1)}%',
                          color: (savingsRate ?? 0) >= 0
                              ? incomeColor(context)
                              : expenseColor(context),
                        ),
                        const SizedBox(height: 8),
                        _row('Transactions', '$txCount'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Expense vs last month: ',
                        style: TextStyle(fontSize: 14)),
                    _DeltaLabel(current: expense, previous: prevExpense),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Top Categories',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (topCategories.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('No expenses this month.'),
                  )
                else
                  ...topCategories.map((entry) {
                    final prevValue = prevCategoryTotals[entry.key] ?? 0;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              CategoryColors.forCategory(entry.key),
                          radius: 10,
                        ),
                        title: Text(entry.key),
                        subtitle: _DeltaLabel(
                            current: entry.value, previous: prevValue),
                        trailing: Text(formatMoney(entry.value),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _row(String label, String value,
      {Color? color, bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: color, fontSize: 15)),
      ],
    );
  }
}

/// Shows the month-over-month change with a direction arrow.
class _DeltaLabel extends StatelessWidget {
  final int current;
  final int previous;
  const _DeltaLabel({required this.current, required this.previous});

  @override
  Widget build(BuildContext context) {
    final delta = current - previous;
    if (previous == 0 && current == 0) {
      return const Text('—', style: TextStyle(fontSize: 12));
    }
    final up = delta > 0;
    final flat = delta == 0;
    final color = flat
        ? Colors.grey
        : up
            ? expenseColor(context)
            : incomeColor(context);
    final icon = flat
        ? Icons.remove
        : up
            ? Icons.arrow_upward
            : Icons.arrow_downward;
    final pct = previous > 0
        ? ' (${(delta.abs() / previous * 100).toStringAsFixed(0)}%)'
        : '';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        Text('${formatMoney(delta.abs())}$pct',
            style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
