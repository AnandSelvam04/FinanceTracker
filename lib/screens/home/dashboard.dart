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

/// The latest few transactions, whatever period the charts above show — so
/// "did that payment go in?" is answered on the dashboard, without switching
/// to the Transactions tab and scrolling. Hidden until there is something.
class _RecentTransactions extends StatelessWidget {
  final ExpenseProvider provider;
  final VoidCallback onSeeAll;
  const _RecentTransactions({required this.provider, required this.onSeeAll});

  static const _count = 5;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // Rows are kept newest first; skip anything dated ahead of today.
    final rows = provider.expenses
        .where((e) => !e.date.isAfter(now))
        .take(_count)
        .toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    final accounts = context.watch<AccountProvider>();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: SectionHeader('Recent transactions')),
              TextButton(onPressed: onSeeAll, child: const Text('See all')),
            ],
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final e in rows)
                  _RecentRow(
                    expense: e,
                    symbol: accounts.accountById(e.accountId)?.symbol,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One compact row in [_RecentTransactions]; tap for edit/duplicate/delete.
class _RecentRow extends StatelessWidget {
  final Expense expense;

  /// The source account's currency symbol; null for the base currency.
  final String? symbol;
  const _RecentRow({required this.expense, this.symbol});

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final magnitude = symbol == null
        ? formatMoney(e.amount.abs())
        : formatMoneyIn(symbol!, e.amount.abs());
    // Same sign and colour conventions as the Transactions list.
    final moneyIn = e.isIncome || e.isRefund;
    final amount =
        e.isTransfer ? magnitude : '${moneyIn ? '+' : '-'}$magnitude';
    final color = moneyIn
        ? incomeColor(context)
        : e.isTransfer
            ? transferColor(context)
            : expenseColor(context);
    return ListTile(
      dense: true,
      leading: e.isTransfer
          ? CircleAvatar(
              radius: 16,
              backgroundColor: transferAvatarColor(context),
              child: Icon(Icons.swap_horiz,
                  size: 18, color: transferColor(context)),
            )
          : CategoryAvatar(category: e.category, radius: 16),
      title: Text(
        e.description.isEmpty ? '(no description)' : e.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${e.isTransfer ? 'Transfer' : e.category} · ${formatDateWithDay(e.date)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(amount,
          style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      onTap: () => transactionRowActions(context, e,
          onDelete: () => _deleteWithUndo(context, e)),
    );
  }

  /// Deletes [e] (picked explicitly from the row's action sheet) and offers
  /// an Undo that puts the same row back.
  static Future<void> _deleteWithUndo(BuildContext context, Expense e) async {
    final expenses = context.read<ExpenseProvider>();
    final accounts = context.read<AccountProvider>();
    final messenger = ScaffoldMessenger.of(context);
    await expenses.deleteExpense(e.id!);
    await accounts.refreshBalances();
    messenger.showSnackBar(SnackBar(
      content: const Text('Transaction deleted'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          await expenses.addExpense(e);
          await accounts.refreshBalances();
        },
      ),
    ));
  }
}

/// The transactions behind one pie slice: a total plus the rows that make it
/// up, shown when the user taps a category on the dashboard chart.
class _CategoryDetailSheet extends StatelessWidget {
  final String category;
  final String period;
  final int total;
  final List<Expense> rows;
  final int Function(Expense) baseAmountOf;
  final void Function(Expense) onEdit;

  const _CategoryDetailSheet({
    required this.category,
    required this.period,
    required this.total,
    required this.rows,
    required this.baseAmountOf,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: bottomSheetPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryAvatar(category: category, radius: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(category,
                    style: Theme.of(context).textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis),
              ),
              Text(formatMoney(total),
                  style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$period · ${rows.length} transaction'
            '${rows.length == 1 ? '' : 's'}',
            style: TextStyle(color: mutedTextColor(context), fontSize: 13),
          ),
          const Divider(height: 20),
          // Flexible + shrinkWrap keeps a short list compact but lets a long one
          // scroll inside the sheet rather than overflow.
          Flexible(
            child: rows.isEmpty
                ? Text('No transactions in this category.',
                    style: TextStyle(color: mutedTextColor(context)))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final e = rows[i];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            e.description.isEmpty
                                ? '(no description)'
                                : e.description,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(formatDateWithDay(e.date)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(formatMoney(baseAmountOf(e)),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(width: 4),
                            Icon(Icons.chevron_right,
                                size: 18, color: mutedTextColor(context)),
                          ],
                        ),
                        // Tap a row to edit that transaction. onEdit closes
                        // this sheet and opens the editor over the dashboard, so
                        // the totals refresh with the change on save.
                        onTap: () => onEdit(e),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Headline spend with an animated count-up. Income is not repeated here:
/// the summary cards directly below already show it.
class _TotalHeadline extends StatelessWidget {
  final String label;
  final int amount;
  const _TotalHeadline({
    required this.label,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
            color: mutedTextColor(context),
          ),
        ),
        const SizedBox(height: 2),
        // ShaderMask paints the count-up total with the brand gradient. The
        // white base color is what the srcIn blend replaces with the gradient.
        ShaderMask(
          shaderCallback: (bounds) =>
              brandGradient(context).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: AnimatedMoney(
            value: amount,
            format: formatMoney,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

/// Income and Expenses shown side by side as two summary cards under the
/// headline total — the at-a-glance split the attached designs lead with.
class _SummaryPills extends StatelessWidget {
  final int income;
  final int expense;
  const _SummaryPills({required this.income, required this.expense});

  @override
  Widget build(BuildContext context) {
    // The headline above is already the period's spend, so the second card
    // shows what is left after it (income minus spend) rather than repeating
    // the same figure.
    final net = income - expense;
    return Row(
      children: [
        Expanded(
          child: _SummaryPill(
            label: 'Income',
            amount: income,
            icon: Icons.south_west,
            color: incomeColor(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryPill(
            label: net < 0 ? 'Overspent' : 'Saved',
            amount: net.abs(),
            icon: net < 0 ? Icons.trending_down : Icons.savings_outlined,
            color: net < 0 ? expenseColor(context) : incomeColor(context),
          ),
        ),
      ],
    );
  }
}

/// A single labelled amount card with a colored icon badge.
class _SummaryPill extends StatelessWidget {
  final String label;
  final int amount;
  final IconData icon;
  final Color color;
  const _SummaryPill({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: dark ? 0.24 : 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600,
                      color: mutedTextColor(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatMoney(amount),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
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

/// The period's top three merchants under the category chart; hidden when
/// no expense names a merchant.
class _DashboardMerchants extends StatelessWidget {
  final List<Expense> rows;
  final int total;
  final int Function(Expense) baseAmountOf;
  const _DashboardMerchants({
    required this.rows,
    required this.total,
    required this.baseAmountOf,
  });

  @override
  Widget build(BuildContext context) {
    final merchants = topMerchants(rows, baseAmountOf, limit: 3);
    if (merchants.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TopMerchantsCard(merchants: merchants, periodTotal: total),
    );
  }
}

/// How much of the month's overall budget is used, as a ring beside what is
/// left (or how far over it is) — read at a glance, where the Budgets tab
/// takes a tap. Tapping it opens that tab. Renders nothing when no overall
/// budget is set for the month.
class _BudgetRing extends StatelessWidget {
  /// Overall cap and spend for the month, in base-currency minor units.
  final int cap;
  final int spent;
  final VoidCallback onTap;
  const _BudgetRing(
      {required this.cap, required this.spent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (cap <= 0) return const SizedBox.shrink();
    final left = cap - spent;
    final over = left < 0;
    final ratio = (spent / cap).clamp(0.0, 1.0).toDouble();
    final percent = (spent * 100 / cap).round();
    final color = over
        ? dangerColor(context)
        : percent >= 90
            ? warningColor(context)
            : incomeColor(context);
    // The ring gives the share away even with the figures masked.
    final hidden = CurrencyFormat.hideAmounts;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Haptics.tick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                Semantics(
                  label: hidden ? 'Budget used' : '$percent% of budget used',
                  excludeSemantics: true,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: hidden ? 0 : ratio),
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) =>
                              CircularProgressIndicator(
                            value: value,
                            strokeWidth: 6,
                            strokeCap: StrokeCap.round,
                            color: color,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                          ),
                        ),
                        Center(
                          child: Text(
                            hidden ? '••' : '$percent%',
                            // Sized to the ring, not to the text setting.
                            textScaler: TextScaler.noScaling,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        over
                            ? 'Over budget by ${formatMoney(-left)}'
                            : '${formatMoney(left)} left to spend',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatMoneyRounded(spent)} of '
                        '${formatMoneyRounded(cap)} budget',
                        style: TextStyle(
                            fontSize: 12, color: mutedTextColor(context)),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: mutedTextColor(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A run of days without spending, shown once it is two or more: a small
/// reason to open the app and keep it going. Hidden otherwise.
class _StreakChip extends StatelessWidget {
  final int days;
  const _StreakChip({required this.days});

  @override
  Widget build(BuildContext context) {
    if (days < 2) return const SizedBox.shrink();
    final warn = warningColor(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: warn.withValues(alpha: dark ? 0.2 : 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department, size: 18, color: warn),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '$days no-spend days in a row',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The month in plain words: what [dashboardInsights] found worth saying,
/// each line with an icon tinted by whether it is good news.
class _InsightsCard extends StatelessWidget {
  final List<Insight> insights;
  const _InsightsCard({required this.insights});

  static IconData _icon(InsightKind kind) => switch (kind) {
        InsightKind.budget => Icons.donut_large,
        InsightKind.category => Icons.category_outlined,
        InsightKind.total => Icons.compare_arrows,
        InsightKind.savings => Icons.savings_outlined,
        InsightKind.biggest => Icons.receipt_long_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          const SectionHeader('Insights'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(
                children: [
                  for (final insight in insights)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Builder(builder: (context) {
                            final color = switch (insight.tone) {
                              InsightTone.good => incomeColor(context),
                              InsightTone.warn => warningColor(context),
                              InsightTone.neutral => infoColor(context),
                            };
                            return Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color:
                                    color.withValues(alpha: dark ? 0.24 : 0.14),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(_icon(insight.kind),
                                  size: 18, color: color),
                            );
                          }),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(insight.text,
                                style: const TextStyle(fontSize: 14)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
