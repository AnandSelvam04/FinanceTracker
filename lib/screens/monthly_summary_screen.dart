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

part 'monthly_summary/category_widgets.dart';
part 'monthly_summary/how_you_paid.dart';
part 'monthly_summary/year_in_review.dart';

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
