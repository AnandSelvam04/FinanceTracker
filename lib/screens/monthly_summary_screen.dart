import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/expense.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../services/excel_export.dart';
import '../services/statement_pdf.dart';
import '../widgets/section_header.dart';
import '../widgets/category_avatar.dart';
import '../utils/alerts.dart' show calendarDaysBetween;
import '../utils/app_colors.dart';
import '../utils/category_colors.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/insets.dart';
import '../utils/payment_split.dart';
import '../utils/merchant_summary.dart';
import '../utils/year_review.dart';
import '../widgets/month_selector.dart';
import '../widgets/top_merchants_card.dart';

/// What the report covers: a calendar month, a Monday–Sunday week, a
/// calendar year (the year in review) or any dates the user picks.
enum _PeriodMode { month, week, year, custom }

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

  /// The dates of the Custom report, both inclusive. Starts as the last 30
  /// days.
  late DateTimeRange _custom = DateTimeRange(
    start: _plusDays(_dateOnly(DateTime.now()), -29),
    end: _dateOnly(DateTime.now()),
  );

  /// Currently selected category filter, or null for "All Categories".
  String? _category;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _mondayOf(DateTime d) {
    // DateTime.weekday: Mon = 1 .. Sun = 7.
    return _plusDays(_dateOnly(d), -(d.weekday - 1));
  }

  /// [d] moved by [days] calendar days. A `Duration` adds 24-hour blocks,
  /// which lands on 23:00 or 01:00 across a daylight-saving change and would
  /// start the week on Sunday night.
  static DateTime _plusDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLoaded());
  }

  // --- Period boundaries -----------------------------------------------------

  DateTime get _rangeStart => switch (_mode) {
        _PeriodMode.week => _weekStart,
        _PeriodMode.month => DateTime(_year, _month, 1),
        _PeriodMode.year => DateTime(_year),
        _PeriodMode.custom => _custom.start,
      };

  /// Exclusive upper bound of the current period.
  DateTime get _rangeEnd => switch (_mode) {
        _PeriodMode.week => _plusDays(_weekStart, 7),
        // DateTime normalizes month 13 to January of the next year.
        _PeriodMode.month => DateTime(_year, _month + 1, 1),
        _PeriodMode.year => DateTime(_year + 1),
        _PeriodMode.custom => _plusDays(_custom.end, 1),
      };

  /// Start of the period this one is compared with: the week, month or year
  /// before, or for custom dates the same number of days just before them.
  DateTime get _prevStart => switch (_mode) {
        _PeriodMode.week => _plusDays(_weekStart, -7),
        _PeriodMode.month => DateTime(_year, _month - 1, 1),
        _PeriodMode.year => DateTime(_year - 1),
        _PeriodMode.custom => _plusDays(
            _custom.start, -calendarDaysBetween(_rangeStart, _rangeEnd)),
      };

  /// Whether today falls inside the period on screen, i.e. it isn't over.
  bool get _inProgress {
    final today = _dateOnly(DateTime.now());
    return !today.isBefore(_rangeStart) && today.isBefore(_rangeEnd);
  }

  /// End of the stretch of the previous period to compare against. While the
  /// period on screen is still running, that is the same number of days into
  /// the previous one: ten days of this month against the whole of last
  /// month always looked like a big drop in spending.
  DateTime get _prevEnd {
    if (!_inProgress) return _rangeStart;
    final today = _dateOnly(DateTime.now());
    final elapsed = calendarDaysBetween(_rangeStart, today) + 1;
    // Never past the previous period's own end (a 31-day month against a
    // 28-day one).
    final end = _plusDays(_prevStart, elapsed);
    return end.isAfter(_rangeStart) ? _rangeStart : end;
  }

  /// What the previous period is called in "Expense vs last …".
  String get _prevName => switch (_mode) {
        _PeriodMode.week => 'last week',
        _PeriodMode.month => 'last month',
        _PeriodMode.year => 'last year',
        _PeriodMode.custom => () {
            final days = calendarDaysBetween(_rangeStart, _rangeEnd);
            return days == 1 ? 'the day before' : 'the $days days before';
          }(),
      };

  void _ensureLoaded() {
    final provider = context.read<ExpenseProvider>();
    // A week can straddle a month/year boundary, and the previous period may
    // fall in an earlier year, so load every year the two ranges can touch.
    // Custom dates can span several years.
    provider.ensureYearsLoaded({
      for (var y = _prevStart.year; y <= _plusDays(_rangeEnd, -1).year; y++) y,
    });
  }

  /// The period as it appears in a file name.
  String get _periodLabel => switch (_mode) {
        _PeriodMode.week =>
          '${formatIsoDate(_weekStart)}_${formatIsoDate(_plusDays(_weekStart, 6))}',
        _PeriodMode.month => '$_year-${_month.toString().padLeft(2, '0')}',
        _PeriodMode.year => '$_year',
        _PeriodMode.custom =>
          '${formatIsoDate(_custom.start)}_${formatIsoDate(_custom.end)}',
      };

  /// The period as it reads on screen and inside an exported report.
  String get _periodHeading => switch (_mode) {
        _PeriodMode.week =>
          '${formatShortDate(_weekStart)}  –  ${formatShortDate(_plusDays(_weekStart, 6))}',
        _PeriodMode.month => '${monthName(_month)} $_year',
        _PeriodMode.year => '$_year',
        _PeriodMode.custom =>
          '${formatShortDate(_custom.start)}  –  ${formatShortDate(_custom.end)}',
      };

  Future<void> _pickCustomRange() async {
    final today = _dateOnly(DateTime.now());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year + 1, 12, 31),
      initialDateRange: _custom,
      helpText: 'Report dates',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _custom = DateTimeRange(
          start: _dateOnly(picked.start), end: _dateOnly(picked.end));
      _category = null;
    });
    _ensureLoaded();
  }

  void _stepWeek(int delta) {
    setState(() {
      _weekStart = _plusDays(_weekStart, 7 * delta);
      _category = null;
    });
    _ensureLoaded();
  }

  /// A year or a custom stretch gets the month and category breakdown too.
  bool get _longPeriod =>
      _mode == _PeriodMode.year || _mode == _PeriodMode.custom;

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
        title: _mode == _PeriodMode.year
            ? 'Finance Tracker — Year in review'
            : 'Finance Tracker Statement',
        periodLabel: _periodLabel,
        transactions: transactions,
        ratesByAccount: rates,
        breakdown: _longPeriod,
      );
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Statement $_periodLabel',
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  /// Shares the period as an Excel workbook: a summary, the transactions,
  /// spending by category and (over more than a month) month by month.
  Future<void> _shareExcel(List<Expense> transactions) async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<ExpenseProvider>();
    final accounts = context.read<AccountProvider>().accounts;
    if (transactions.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No transactions to include.')),
      );
      return;
    }
    try {
      final file = await ExcelExport.write(
        ExcelExport.reportSheets(
          periodLabel: _periodHeading.replaceAll('  ', ' '),
          transactions: transactions,
          baseAmountOf: provider.baseAmountOf,
          accountNames: {
            for (final a in accounts)
              if (a.id != null) a.id!: a.name,
          },
        ),
        name: 'report_$_periodLabel',
      );
      await Share.shareXFiles(
        [XFile(file.path, mimeType: ExcelExport.mimeType)],
        subject: 'Finance Tracker report $_periodLabel',
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
        final prevExpense = sumBase(prevRows.where((e) => e.isExpense));

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

        final merchants = topMerchants(expenseRows, provider.baseAmountOf);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Reports'),
            actions: [
              IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                tooltip: 'Share PDF statement',
                onPressed: () => _sharePdf(rows),
              ),
              IconButton(
                icon: const Icon(Icons.table_view),
                tooltip: 'Share as Excel',
                onPressed: () => _shareExcel(rows),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: scrollPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // What the report covers. No icons: four labelled segments
                // only just fit a narrow phone as it is.
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<_PeriodMode>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      padding: WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 4)),
                    ),
                    segments: const [
                      ButtonSegment(
                          value: _PeriodMode.week, label: Text('Week')),
                      ButtonSegment(
                          value: _PeriodMode.month, label: Text('Month')),
                      ButtonSegment(
                          value: _PeriodMode.year, label: Text('Year')),
                      ButtonSegment(
                          value: _PeriodMode.custom, label: Text('Custom')),
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
                if (_mode == _PeriodMode.month || _mode == _PeriodMode.year)
                  MonthSelector(
                    // Rebuilt when the mode changes or a month is opened
                    // from the year's chart: the selector keeps its own
                    // year and month once built.
                    key: ValueKey('sel-${_mode.name}-$_year-$_month'),
                    initialYear: _year,
                    initialMonth: _month,
                    yearOnly: _mode == _PeriodMode.year,
                    onChanged: (y, m) {
                      setState(() {
                        _year = y;
                        _month = m;
                        _category = null;
                      });
                      _ensureLoaded();
                    },
                  )
                else if (_mode == _PeriodMode.week)
                  _WeekSelector(
                    heading: _periodHeading,
                    onPrev: () => _stepWeek(-1),
                    onNext: () => _stepWeek(1),
                  )
                else
                  Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.date_range),
                      label: Text(_periodHeading),
                      onPressed: _pickCustomRange,
                    ),
                  ),
                const SizedBox(height: 8),
                _CategoryFilter(
                  // Reset the dropdown's internal state whenever the period
                  // changes, so it can't keep showing a category that isn't in
                  // the newly selected period.
                  key: ValueKey(
                      'cat-${_mode.name}-${formatIsoDate(_rangeStart)}'),
                  categories: sortedCategories.map((e) => e.key).toList(),
                  selected: selectedCategory,
                  onChanged: (c) => setState(() => _category = c),
                ),
                const SizedBox(height: 12),
                if (selectedCategory == null && _mode == _PeriodMode.year) ...[
                  _YearInReview(
                    review: YearReview.from(rows,
                        year: _year, baseAmountOf: provider.baseAmountOf),
                    onMonthTap: (m) {
                      setState(() {
                        _mode = _PeriodMode.month;
                        _month = m;
                        _category = null;
                      });
                      _ensureLoaded();
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                if (selectedCategory == null)
                  ..._buildOverview(
                    context: context,
                    income: income,
                    expense: expense,
                    prevExpense: prevExpense,
                    txCount: rows.length,
                    expenseRows: expenseRows,
                    baseAmountOf: provider.baseAmountOf,
                    sortedCategories: sortedCategories,
                    prevCategoryTotals: prevCategoryTotals,
                    merchants: merchants,
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
    required List<Expense> expenseRows,
    required int Function(Expense) baseAmountOf,
    required List<MapEntry<String, int>> sortedCategories,
    required Map<String, int> prevCategoryTotals,
    required List<MerchantTotal> merchants,
  }) {
    final net = income - expense;
    final savingsRate = income > 0 ? (net / income) * 100 : null;
    final topCategories = sortedCategories.take(6).toList();
    final categoryTotal = sortedCategories.fold<int>(0, (s, e) => s + e.value);

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
                  color:
                      net >= 0 ? incomeColor(context) : expenseColor(context),
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
      // Wraps rather than overflows on a narrow phone, where the label and
      // the delta don't fit on one line.
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
              // "same days" only reads right against a named period.
              _inProgress && _mode != _PeriodMode.custom
                  ? 'Expense vs same days $_prevName: '
                  : 'Expense vs $_prevName: ',
              style: const TextStyle(fontSize: 14)),
          _DeltaLabel(current: expense, previous: prevExpense),
        ],
      ),
      const SizedBox(height: 16),
      _HowYouPaid(rows: expenseRows, baseAmountOf: baseAmountOf),
      const SizedBox(height: 16),
      const SectionHeader('Top categories'),
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
      if (merchants.isNotEmpty) ...[
        const SizedBox(height: 16),
        TopMerchantsCard(merchants: merchants, periodTotal: expense),
      ],
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
      isExpanded: true,
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
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text(formatMoney(amount),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: fraction,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text('$pct% of spend',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: mutedTextColor(context))),
                      ),
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
                          style: Theme.of(context).textTheme.titleLarge,
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
                        style: Theme.of(context).textTheme.titleLarge),
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

/// How the period's spending was paid — credit cards, bank, UPI, cash — with
/// the accounts behind each, largest first.
///
/// Replaces a flat per-account list, which showed which card was used but
/// not how much of the month went on cards altogether, against bank, UPI and
/// cash. The Accounts screen shows balances, which are positions rather than
/// periods; this is what answers "how much did I put on my cards".
class _HowYouPaid extends StatelessWidget {
  final List<Expense> rows;
  final int Function(Expense) baseAmountOf;
  const _HowYouPaid({required this.rows, required this.baseAmountOf});

  static Color colorOf(BuildContext context, PayMethod m) {
    final scheme = Theme.of(context).colorScheme;
    return switch (m) {
      PayMethod.creditCard => scheme.primary,
      PayMethod.bank => scheme.tertiary,
      PayMethod.upi => infoColor(context),
      PayMethod.cash => warningColor(context),
      PayMethod.other => mutedTextColor(context),
    };
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountProvider>();
    final split = paymentSplit(rows, baseAmountOf, accounts.accountById);
    if (split.isEmpty) return const SizedBox.shrink();
    final total = split.fold<int>(0, (s, m) => s + m.total);
    final muted = mutedTextColor(context);
    String share(int v) => '${(v / total * 100).round()}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('How you paid'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // One bar, a segment per method, so the mix reads at a glance.
                Semantics(
                  label: 'Spending by payment method',
                  value: [
                    for (final m in split) '${m.method.label} ${share(m.total)}'
                  ].join(', '),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 10,
                      child: Row(
                        children: [
                          for (final m in split)
                            Expanded(
                              // At least a sliver for a tiny share.
                              flex: (m.total * 1000 ~/ total).clamp(8, 1000),
                              child:
                                  ColoredBox(color: colorOf(context, m.method)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final m in split) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: colorOf(context, m.method),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(m.method.label,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(share(m.total),
                              style: TextStyle(fontSize: 12, color: muted)),
                        ),
                        Text(formatMoney(m.total),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  // The accounts behind a method — each card, each bank —
                  // unless the only part is spending with no account.
                  if (m.parts.length > 1 || m.parts.single.accountId != null)
                    for (final p in m.parts)
                      Padding(
                        padding:
                            const EdgeInsets.only(left: 20, top: 2, bottom: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                accounts.accountById(p.accountId)?.name ??
                                    'No account',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: muted,
                                  fontStyle: p.accountId == null
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                              ),
                            ),
                            Text(formatMoney(p.total),
                                style: TextStyle(fontSize: 13, color: muted)),
                          ],
                        ),
                      ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The year at a glance: spending month by month (tap a bar to open that
/// month) and the figures worth remembering about it.
class _YearInReview extends StatelessWidget {
  final YearReview review;
  final ValueChanged<int> onMonthTap;
  const _YearInReview({required this.review, required this.onMonthTap});

  @override
  Widget build(BuildContext context) {
    if (review.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final muted = mutedTextColor(context);
    final peak = review.monthlyExpense
        .fold<int>(0, (m, v) => v > m ? v : m)
        .clamp(1, 1 << 62);
    final highest = review.highestMonth;
    final lowest = review.lowestMonth;
    final bestSaving = review.bestSavingMonth;
    final biggest = review.biggest;

    Widget fact(IconData icon, String label, String value, {String? detail}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label),
                    if (detail != null)
                      Text(detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Month by month'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var m = 1; m <= 12; m++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: '${monthName(m)}: '
                            '${formatMoney(review.monthlyExpense[m - 1])} '
                            'spent',
                        excludeSemantics: true,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => onMonthTap(m),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Flexible(
                                child: FractionallySizedBox(
                                  // A month with a net refund has nothing
                                  // to draw.
                                  heightFactor:
                                      (review.monthlyExpense[m - 1] / peak)
                                          .clamp(0.0, 1.0),
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 3),
                                    decoration: BoxDecoration(
                                      color: m == highest
                                          ? expenseColor(context)
                                          : scheme.primary,
                                      borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(4)),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(monthName(m).substring(0, 1),
                                  style: TextStyle(fontSize: 11, color: muted)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const SectionHeader('Year in review'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                fact(Icons.functions, 'Average month',
                    formatMoney(review.averageMonthlyExpense)),
                if (highest != null)
                  fact(Icons.arrow_upward, 'Highest spending',
                      formatMoney(review.monthlyExpense[highest - 1]),
                      detail: monthName(highest)),
                if (lowest != null)
                  fact(Icons.arrow_downward, 'Lowest spending',
                      formatMoney(review.monthlyExpense[lowest - 1]),
                      detail: monthName(lowest)),
                if (bestSaving != null)
                  fact(
                      Icons.savings_outlined,
                      'Most saved',
                      formatMoneySigned(review.monthlyIncome[bestSaving - 1] -
                          review.monthlyExpense[bestSaving - 1]),
                      detail: monthName(bestSaving)),
                if (biggest != null)
                  fact(Icons.receipt_long_outlined, 'Biggest expense',
                      formatMoney(biggest.amount),
                      detail: '${biggest.description} · '
                          '${formatShortDate(biggest.date)}'),
                fact(Icons.event_available_outlined, 'No-spend days',
                    '${review.noSpendDays}'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
