import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/expense.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../services/statement_pdf.dart';
import '../widgets/category_avatar.dart';
import '../utils/app_colors.dart';
import '../utils/category_colors.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/insets.dart';
import '../widgets/month_selector.dart';

/// Whether the summary is scoped to a calendar month or a single week.
enum _PeriodMode { month, week }

class MonthlySummaryScreen extends StatefulWidget {
  const MonthlySummaryScreen({super.key});

  @override
  State<MonthlySummaryScreen> createState() => _MonthlySummaryScreenState();
}

class _MonthlySummaryScreenState extends State<MonthlySummaryScreen> {
  _PeriodMode _mode = _PeriodMode.month;
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;

  /// Monday of the selected week (date-only). Weeks run Monday–Sunday.
  late DateTime _weekStart = _mondayOf(DateTime.now());

  /// Currently selected category filter, or null for "All Categories".
  String? _category;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _mondayOf(DateTime d) {
    final day = _dateOnly(d);
    // DateTime.weekday: Mon = 1 .. Sun = 7.
    return day.subtract(Duration(days: day.weekday - 1));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLoaded());
  }

  // --- Period boundaries -----------------------------------------------------

  DateTime get _rangeStart => _mode == _PeriodMode.week
      ? _weekStart
      : DateTime(_year, _month, 1);

  /// Exclusive upper bound of the current period.
  DateTime get _rangeEnd => _mode == _PeriodMode.week
      ? _weekStart.add(const Duration(days: 7))
      // DateTime normalizes month 13 to January of the next year.
      : DateTime(_year, _month + 1, 1);

  DateTime get _prevStart => _mode == _PeriodMode.week
      ? _weekStart.subtract(const Duration(days: 7))
      : (_month == 1 ? DateTime(_year - 1, 12, 1) : DateTime(_year, _month - 1, 1));

  DateTime get _prevEnd => _rangeStart;

  void _ensureLoaded() {
    final provider = context.read<ExpenseProvider>();
    // A week can straddle a month/year boundary, and the previous period may
    // fall in an earlier year, so load every year the two ranges can touch.
    provider.ensureYearsLoaded({
      _rangeStart.year,
      _rangeEnd.subtract(const Duration(days: 1)).year,
      _prevStart.year,
    });
  }

  String get _periodLabel {
    if (_mode == _PeriodMode.week) {
      final end = _weekStart.add(const Duration(days: 6));
      return '${formatIsoDate(_weekStart)}_${formatIsoDate(end)}';
    }
    return '$_year-${_month.toString().padLeft(2, '0')}';
  }

  String get _periodHeading {
    if (_mode == _PeriodMode.week) {
      final end = _weekStart.add(const Duration(days: 6));
      return '${formatShortDate(_weekStart)}  –  ${formatShortDate(end)}';
    }
    return '${monthName(_month)} $_year';
  }

  void _stepWeek(int delta) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * delta));
      _category = null;
    });
    _ensureLoaded();
  }

  Future<void> _sharePdf(List<Expense> transactions) async {
    final messenger = ScaffoldMessenger.of(context);
    final rates = context.read<AccountProvider>().ratesByAccount;
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
        ratesByAccount: rates,
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
    return Consumer<ExpenseProvider>(
      builder: (context, provider, _) {
        final rows = provider.expensesInRange(_rangeStart, _rangeEnd);
        final prevRows = provider.expensesInRange(_prevStart, _prevEnd);

        int sumBase(Iterable<Expense> rs) =>
            rs.fold(0, (s, e) => s + provider.baseAmountOf(e));

        final expenseRows = rows.where((e) => e.isExpense).toList();
        final income = sumBase(rows.where((e) => e.isIncome));
        final expense = sumBase(expenseRows);
        final prevExpense =
            sumBase(prevRows.where((e) => e.isExpense));

        // Category totals for the period (expenses only).
        final categoryTotals = <String, int>{};
        for (final e in expenseRows) {
          categoryTotals[e.category] =
              (categoryTotals[e.category] ?? 0) + provider.baseAmountOf(e);
        }
        final prevCategoryTotals = <String, int>{};
        for (final e in prevRows.where((e) => e.isExpense)) {
          prevCategoryTotals[e.category] =
              (prevCategoryTotals[e.category] ?? 0) + provider.baseAmountOf(e);
        }

        final sortedCategories = categoryTotals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        // Keep the dropdown selection valid as the period changes.
        final selectedCategory =
            (_category != null && categoryTotals.containsKey(_category))
                ? _category
                : null;

        // Spend by account for the period.
        final spendByAccount = <int?, int>{};
        for (final e in expenseRows) {
          spendByAccount[e.accountId] =
              (spendByAccount[e.accountId] ?? 0) + provider.baseAmountOf(e);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Monthly Summary'),
            actions: [
              IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                tooltip: 'Share PDF statement',
                onPressed: () => _sharePdf(rows),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: scrollPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Month vs. week granularity.
                Center(
                  child: SegmentedButton<_PeriodMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: _PeriodMode.month,
                        label: Text('Month'),
                        icon: Icon(Icons.calendar_view_month),
                      ),
                      ButtonSegment(
                        value: _PeriodMode.week,
                        label: Text('Week'),
                        icon: Icon(Icons.calendar_view_week),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) {
                      setState(() {
                        _mode = s.first;
                        _category = null;
                      });
                      _ensureLoaded();
                    },
                  ),
                ),
                const SizedBox(height: 8),
                if (_mode == _PeriodMode.month)
                  MonthSelector(
                    initialYear: _year,
                    initialMonth: _month,
                    onChanged: (y, m) {
                      setState(() {
                        _year = y;
                        _month = m;
                        _category = null;
                      });
                      _ensureLoaded();
                    },
                  )
                else
                  _WeekSelector(
                    heading: _periodHeading,
                    onPrev: () => _stepWeek(-1),
                    onNext: () => _stepWeek(1),
                  ),
                const SizedBox(height: 8),
                _CategoryFilter(
                  // Reset the dropdown's internal state whenever the period
                  // changes, so it can't keep showing a category that isn't in
                  // the newly selected period.
                  key: ValueKey('cat-${_mode.name}-${formatIsoDate(_rangeStart)}'),
                  categories: sortedCategories.map((e) => e.key).toList(),
                  selected: selectedCategory,
                  onChanged: (c) => setState(() => _category = c),
                ),
                const SizedBox(height: 12),
                if (selectedCategory == null)
                  ..._buildOverview(
                    context: context,
                    income: income,
                    expense: expense,
                    prevExpense: prevExpense,
                    txCount: rows.length,
                    spendByAccount: spendByAccount,
                    sortedCategories: sortedCategories,
                    prevCategoryTotals: prevCategoryTotals,
                  )
                else
                  _CategoryFocus(
                    category: selectedCategory,
                    rows: expenseRows
                        .where((e) => e.category == selectedCategory)
                        .toList()
                      ..sort((a, b) => b.date.compareTo(a.date)),
                    total: categoryTotals[selectedCategory] ?? 0,
                    previous: prevCategoryTotals[selectedCategory] ?? 0,
                    baseAmountOf: provider.baseAmountOf,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildOverview({
    required BuildContext context,
    required int income,
    required int expense,
    required int prevExpense,
    required int txCount,
    required Map<int?, int> spendByAccount,
    required List<MapEntry<String, int>> sortedCategories,
    required Map<String, int> prevCategoryTotals,
  }) {
    final net = income - expense;
    final savingsRate = income > 0 ? (net / income) * 100 : null;
    final topCategories = sortedCategories.take(6).toList();
    final categoryTotal =
        sortedCategories.fold<int>(0, (s, e) => s + e.value);

    return [
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _row('Income', formatMoney(income), color: incomeColor(context)),
              const SizedBox(height: 8),
              _row('Expense', formatMoney(expense),
                  color: expenseColor(context)),
              const Divider(),
              _row('Net', formatMoneySigned(net),
                  color: net >= 0 ? incomeColor(context) : expenseColor(context),
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
          Text('Expense vs last ${_mode == _PeriodMode.week ? 'week' : 'month'}: ',
              style: const TextStyle(fontSize: 14)),
          _DeltaLabel(current: expense, previous: prevExpense),
        ],
      ),
      const SizedBox(height: 16),
      _SpendByAccount(totals: spendByAccount),
      const SizedBox(height: 16),
      const Text('Top Categories',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      if (topCategories.isEmpty)
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('No expenses this period.'),
        )
      else
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                for (final entry in topCategories)
                  _CategoryProgressRow(
                    category: entry.key,
                    amount: entry.value,
                    previous: prevCategoryTotals[entry.key] ?? 0,
                    total: categoryTotal,
                    onTap: () => setState(() => _category = entry.key),
                  ),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _row(String label, String value, {Color? color, bool bold = false}) {
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

/// Week stepper mirroring [MonthSelector], showing the selected week's range.
class _WeekSelector extends StatelessWidget {
  final String heading;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _WeekSelector({
    required this.heading,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous week',
          onPressed: onPrev,
        ),
        Text(heading, style: const TextStyle(fontSize: 14)),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next week',
          onPressed: onNext,
        ),
      ],
    );
  }
}

/// Dropdown that scopes the summary to a single category (or all of them).
class _CategoryFilter extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onChanged;
  const _CategoryFilter({
    super.key,
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: selected,
      decoration: const InputDecoration(
        labelText: 'Category',
        prefixIcon: Icon(Icons.filter_list),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('All Categories'),
        ),
        ...categories.map((c) => DropdownMenuItem<String?>(
              value: c,
              child: Text(c, overflow: TextOverflow.ellipsis),
            )),
      ],
      onChanged: onChanged,
    );
  }
}

/// One category row with a share-of-spend progress bar, a percentage, and the
/// month-over-month delta. Tapping it drills into that category's transactions.
class _CategoryProgressRow extends StatelessWidget {
  final String category;
  final int amount;
  final int previous;
  final int total;
  final VoidCallback onTap;
  const _CategoryProgressRow({
    required this.category,
    required this.amount,
    required this.previous,
    required this.total,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = CategoryColors.forCategory(category);
    final fraction = total > 0 ? (amount / total).clamp(0.0, 1.0) : 0.0;
    final pct = total > 0 ? (amount / total * 100).round() : 0;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            CategoryAvatar(category: category, radius: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(category,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text(formatMoney(amount),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 7,
                      backgroundColor: color.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('$pct% of spend',
                          style: TextStyle(
                              fontSize: 12, color: mutedTextColor(context))),
                      const Spacer(),
                      _DeltaLabel(current: amount, previous: previous),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The transactions behind one category for the selected period, shown when a
/// category is picked in the filter.
class _CategoryFocus extends StatelessWidget {
  final String category;
  final List<Expense> rows;
  final int total;
  final int previous;
  final int Function(Expense) baseAmountOf;
  const _CategoryFocus({
    required this.category,
    required this.rows,
    required this.total,
    required this.previous,
    required this.baseAmountOf,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CategoryAvatar(category: category, radius: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(category,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        '${rows.length} transaction'
                        '${rows.length == 1 ? '' : 's'}',
                        style: TextStyle(
                            color: mutedTextColor(context), fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatMoney(total),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    _DeltaLabel(current: total, previous: previous),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('No transactions in this category for the period.',
                style: TextStyle(color: mutedTextColor(context))),
          )
        else
          ...rows.map((e) => Card(
                child: ListTile(
                  leading: CategoryAvatar(category: category),
                  title: Text(
                      e.description.isEmpty
                          ? '(no description)'
                          : e.description,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(formatDateWithDay(e.date)),
                  trailing: Text(formatMoney(baseAmountOf(e)),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              )),
      ],
    );
  }
}

/// Shows the change against the comparison period with a direction arrow.
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
        ? mutedTextColor(context)
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

/// Spend for the period per account, largest first.
///
/// The Accounts screen shows balances, which are positions rather than
/// periods — this is what answers "which card did I actually use this period".
class _SpendByAccount extends StatelessWidget {
  final Map<int?, int> totals;
  const _SpendByAccount({required this.totals});

  @override
  Widget build(BuildContext context) {
    if (totals.isEmpty) return const SizedBox.shrink();
    final accounts = context.watch<AccountProvider>();
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final periodTotal = totals.values.fold<int>(0, (sum, v) => sum + v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Spend by Account',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            accounts.accountById(entry.key)?.name ??
                                'No account',
                            style: TextStyle(
                              fontStyle: entry.key == null
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (periodTotal > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Text(
                              '${(entry.value / periodTotal * 100).round()}%',
                              style: TextStyle(
                                  fontSize: 12, color: mutedTextColor(context)),
                            ),
                          ),
                        Text(formatMoney(entry.value),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
