part of '../home_screen.dart';

class _DashboardView extends StatelessWidget {
  final int selectedYear;
  final int selectedMonth;
  final bool yearView;
  final void Function(int year, int month) onMonthChanged;
  final void Function(bool isYear) onViewToggle;
  final Future<void> Function(TxTemplate template) onQuickAdd;
  final Future<void> Function() onRefresh;
  final VoidCallback onAddExpense;
  final VoidCallback onSeeAllTransactions;
  final VoidCallback onOpenBudgets;

  const _DashboardView({
    required this.selectedYear,
    required this.selectedMonth,
    required this.yearView,
    required this.onMonthChanged,
    required this.onViewToggle,
    required this.onQuickAdd,
    required this.onRefresh,
    required this.onAddExpense,
    required this.onSeeAllTransactions,
    required this.onOpenBudgets,
  });

  /// Opens the transactions that make up one category's slice for the current
  /// period, so tapping the pie answers "what's actually in this?".
  void _showCategoryDetail(
      BuildContext context, ExpenseProvider provider, String category,
      {required bool isYear}) {
    final rows = (isYear
            ? provider.expensesForYear(selectedYear).where((e) => e.isExpense)
            : provider.spendingForMonth(selectedYear, selectedMonth))
        .where((e) => e.category == category)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final total = rows.fold<int>(0, (s, e) => s + provider.baseAmountOf(e));
    final period =
        isYear ? '$selectedYear' : formatMonthYear(selectedYear, selectedMonth);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _CategoryDetailSheet(
        category: category,
        period: period,
        total: total,
        rows: rows,
        baseAmountOf: provider.baseAmountOf,
        // Close the drill-down sheet first (with its own context), then open
        // the editor over the dashboard using the still-mounted outer context —
        // the sheet's context is defunct once it is popped.
        onEdit: (e) {
          Navigator.pop(sheetContext);
          transactionRowActions(context, e);
        },
      ),
    );
  }

  /// The month's overall cap, with rollover applied when it is on, or 0 when
  /// none is set.
  int _overallCap(BuildContext context, ExpenseProvider expenses) {
    final budgets = context.watch<BudgetProvider>();
    final rollover = context.watch<SettingsProvider>().budgetRollover;
    final row = budgets.overallBudgetRow(selectedYear, selectedMonth);
    if (row == null) return 0;
    return budgets.capFor(row, expenses, rollover: rollover);
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return selectedYear == now.year && selectedMonth == now.month;
  }

  /// Each dashboard section's widgets, keyed by its [DashboardLayout] id. A
  /// section with nothing to show for the period (no data yet, or a chart
  /// that only makes sense for a month) is simply absent.
  Map<String, List<Widget>> _sections(
      BuildContext context, ExpenseProvider provider) {
    final monthlyExpenses =
        provider.spendingForMonth(selectedYear, selectedMonth);
    final yearlyExpenses = provider
        .expensesForYear(selectedYear)
        .where((e) => e.isExpense)
        .toList();
    final monthlyIncome = provider.incomeForMonth(selectedYear, selectedMonth);
    final yearlyIncome = provider.incomeForYear(selectedYear);
    // The per-period totals below are read straight from the provider; it
    // memoizes each aggregate until the data changes, so repeated calls in
    // one build (and across the other screens) are free.
    final monthTotal = provider.totalForMonth(selectedYear, selectedMonth);
    final yearTotal = provider.totalForYear(selectedYear);
    final rows = yearView ? yearlyExpenses : monthlyExpenses;
    final income = yearView ? yearlyIncome : monthlyIncome;
    // Tell "still loading" apart from "nothing recorded"; the empty text
    // otherwise flashes on every cold start.
    final loading = rows.isEmpty && provider.isLoading;
    // Income alone is still something to show: a month with only income
    // used to show "No expenses" and hide the salary that had come in.
    final empty = !loading && rows.isEmpty && income == 0;
    final hasData = !loading && !empty;
    final now = DateTime.now();

    final figures = <Widget>[
      MonthSelector(
        initialYear: selectedYear,
        initialMonth: selectedMonth,
        yearOnly: yearView,
        onChanged: onMonthChanged,
      ),
      const SizedBox(height: 12),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: false, label: Text('Month')),
          ButtonSegment(value: true, label: Text('Year')),
        ],
        selected: {yearView},
        onSelectionChanged: (s) {
          Haptics.tick();
          onViewToggle(s.first);
        },
      ),
      const SizedBox(height: 16),
      if (loading)
        const DashboardSkeleton()
      else if (empty)
        EmptyState(
          icon: yearView
              ? Icons.savings_outlined
              : Icons.account_balance_wallet_outlined,
          title: yearView
              ? 'Nothing recorded in $selectedYear yet'
              : 'Nothing recorded this month',
          message: yearView
              ? 'Add a transaction to see your yearly breakdown.'
              : 'Track your first expense to see charts and trends.',
          actionLabel: 'Add expense',
          onAction: onAddExpense,
        )
      else ...[
        _TotalHeadline(
          label: yearView
              ? 'Spent in $selectedYear'
              : _isCurrentMonth
                  ? 'Spent this month'
                  : 'Spent in ${formatMonthYear(selectedYear, selectedMonth)}',
          amount: yearView ? yearTotal : monthTotal,
        ),
        const SizedBox(height: 12),
        _SummaryPills(
          income: income,
          expense: yearView ? yearTotal : monthTotal,
        ),
        if (!yearView) ...[
          _BudgetRing(
            cap: _overallCap(context, provider),
            spent: monthTotal,
            onTap: onOpenBudgets,
          ),
          if (_isCurrentMonth)
            _StreakChip(days: noSpendStreak(provider.expenses, now)),
        ],
      ],
    ];

    List<Widget> insights() {
      final previous = DateTime(selectedYear, selectedMonth - 1);
      final found = dashboardInsights(
        year: selectedYear,
        month: selectedMonth,
        now: now,
        thisMonth: monthlyExpenses,
        lastMonth: provider.spendingForMonth(previous.year, previous.month),
        baseAmountOf: provider.baseAmountOf,
        income: monthlyIncome,
        overallCap: _overallCap(context, provider),
        money: formatMoneyRounded,
      );
      return found.isEmpty ? const [] : [_InsightsCard(insights: found)];
    }

    return {
      DashboardLayout.netWorth: const [NetWorthCard()],
      DashboardLayout.quickAdd: [_QuickAddRow(onQuickAdd: onQuickAdd)],
      DashboardLayout.figures: figures,
      if (hasData && !yearView) DashboardLayout.insights: insights(),
      DashboardLayout.shortcuts: const [_ShortcutsRow()],
      DashboardLayout.recent: [
        _RecentTransactions(provider: provider, onSeeAll: onSeeAllTransactions),
      ],
      if (hasData)
        DashboardLayout.categories: [
          const SizedBox(height: 16),
          SectionHeader(yearView
              ? 'Spending by category (year)'
              : 'Spending by category'),
          const SizedBox(height: 4),
          CategoryBarChart(
            totals: yearView
                ? provider.categoryTotalsForYear(selectedYear)
                : provider.categoryTotalsForMonth(selectedYear, selectedMonth),
            onCategoryTap: (c) =>
                _showCategoryDetail(context, provider, c, isYear: yearView),
          ),
        ],
      if (hasData)
        DashboardLayout.merchants: [
          _DashboardMerchants(
            rows: rows,
            total: yearView ? yearTotal : monthTotal,
            baseAmountOf: provider.baseAmountOf,
          ),
        ],
      if (hasData && !yearView)
        DashboardLayout.trends: [
          const SizedBox(height: 16),
          const SectionHeader('Trends (last 12 months)'),
          ExpenseTrendsChart(provider: provider),
        ],
    };
  }

  /// Width from which the dashboard splits into two columns: figures on the
  /// left, charts on the right. Below it a tablet in portrait still gets one
  /// readable column rather than two cramped ones.
  static const _twoColumnWidth = 840.0;

  /// Widest a single column is allowed to stretch on a large screen.
  static const _maxColumnWidth = 720.0;

  @override
  Widget build(BuildContext context) {
    return Consumer<ExpenseProvider>(
      builder: (context, provider, _) {
        // The user's own arrangement (More → Customise home): which sections
        // show, and in what order.
        final order = context.watch<SettingsProvider>().dashboardSections;
        final sections = _sections(context, provider);
        List<Widget> widgetsFor(Iterable<String> ids) => [
              for (final id in ids) ...?sections[id],
            ];

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: LayoutBuilder(builder: (context, constraints) {
            final charts = order
                .where((id) =>
                    DashboardLayout.chartSections.contains(id) &&
                    (sections[id]?.isNotEmpty ?? false))
                .toList();
            final twoColumns =
                constraints.maxWidth >= _twoColumnWidth && charts.isNotEmpty;
            final Widget body;
            if (twoColumns) {
              body = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: widgetsFor(order.where(
                          (id) => !DashboardLayout.chartSections.contains(id))),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(child: Column(children: widgetsFor(charts))),
                ],
              );
            } else {
              body = Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxColumnWidth),
                  child: Column(children: widgetsFor(order)),
                ),
              );
            }
            return SingleChildScrollView(
              // AlwaysScrollable so pull-to-refresh works even when the
              // content is short enough not to overflow.
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: scrollPadding(context, all: 16),
                child: Column(
                  children: [const AlertsBanner(), body],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
