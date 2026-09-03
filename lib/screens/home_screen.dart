import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/expense.dart';
import '../models/tx_template.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/investment_provider.dart';
import '../providers/budget_provider.dart';
import '../providers/recurring_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/template_provider.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import '../services/recurring_service.dart';
import '../utils/alerts.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/insets.dart';
import '../widgets/alerts_banner.dart';
import '../widgets/animated_money.dart';
import '../widgets/empty_state.dart';
import '../widgets/category_avatar.dart';
import '../widgets/category_bar_chart.dart';
import '../widgets/expense_trends_chart.dart';
import '../widgets/month_selector.dart';
import '../widgets/net_worth_card.dart';
import '../widgets/section_header.dart';
import '../widgets/skeleton.dart';
import 'add_expense_screen.dart';
import 'add_investment_screen.dart';
import 'expense_list_screen.dart';
import 'investments_screen.dart';
import 'more_screen.dart';
import 'sms_review_screen.dart';
import 'tutorial_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  bool _yearView = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<ExpenseProvider>();
      // Load current year and previous year (for trends)
      provider.ensureYearLoaded(_selectedYear);
      provider.ensureYearLoaded(_selectedYear - 1);
      context.read<InvestmentProvider>().fetchInvestments();
      context.read<AccountProvider>().fetchAccounts();
      context.read<TemplateProvider>().fetchTemplates();
      // Capture providers before awaiting so we don't read context across
      // async gaps.
      final recurringProvider = context.read<RecurringProvider>();
      final budgetProvider = context.read<BudgetProvider>();
      await recurringProvider.fetchRules();
      // Budgets power both the in-app alerts banner and budget notifications.
      await budgetProvider.fetchBudgets();
      await _postRecurring();
      // Safety net: keep a fresh local backup even if the user never
      // taps "Backup" (data otherwise lives only on this device).
      await BackupService().autoBackupIfDue();
      if (mounted) await _syncNotifications();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _postRecurring();
    }
  }

  /// Materializes any due recurring transactions and refreshes views.
  Future<void> _postRecurring() async {
    final expenseProvider = context.read<ExpenseProvider>();
    final accountProvider = context.read<AccountProvider>();
    final investmentProvider = context.read<InvestmentProvider>();
    final recurringProvider = context.read<RecurringProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final posted = await RecurringService.instance.postDueTransactions();
    if (posted > 0) {
      await expenseProvider.reloadLoadedYears();
      await accountProvider.refreshBalances();
      // SIP rules file into the investments ledger, so refresh it too —
      // otherwise newly posted contributions (and the net-worth total) stay
      // stale until a manual pull-to-refresh.
      await investmentProvider.fetchInvestments();
      await recurringProvider.fetchRules();
      if (mounted) {
        // "item" rather than "transaction": the count can include SIP
        // investment contributions, which aren't expense/income transactions.
        messenger.showSnackBar(SnackBar(
          content: Text((posted == 1
              ? '1 recurring item posted'
              : '$posted recurring items posted')),
        ));
      }
    }
  }

  /// Pull-to-refresh handler for the dashboard: re-reads everything the
  /// dashboard renders so a swipe reconciles the view with the database.
  Future<void> _refreshDashboard() async {
    final expenses = context.read<ExpenseProvider>();
    final accounts = context.read<AccountProvider>();
    final investments = context.read<InvestmentProvider>();
    final templates = context.read<TemplateProvider>();
    await Future.wait([
      expenses.reloadLoadedYears(),
      accounts.fetchAccounts(),
      investments.fetchInvestments(),
      templates.fetchTemplates(),
    ]);
    if (mounted) await accounts.refreshBalances();
  }

  /// Re-arms bill reminders and fires any new budget notifications, honoring
  /// the user's notifications setting.
  Future<void> _syncNotifications() async {
    final settings = context.read<SettingsProvider>();
    final recurring = context.read<RecurringProvider>();
    final budgets = context.read<BudgetProvider>();
    final expenses = context.read<ExpenseProvider>();
    final service = NotificationService.instance;
    if (!settings.notificationsEnabled) {
      await service.cancelAll();
      return;
    }
    await service.requestPermission();
    await service.scheduleBillReminders(recurring.rules);
    final now = DateTime.now();
    final totals = expenses.categoryTotalsForMonth(now.year, now.month);
    final alerts = budgetAlerts(
      budgets: budgets.budgets,
      year: now.year,
      month: now.month,
      spentForCategory: (c) => totals[c] ?? 0,
    );
    await service.notifyBudgetAlerts(alerts, year: now.year, month: now.month);
  }

  Future<void> _quickAddTemplate(TxTemplate template) async {
    final expenseProvider = context.read<ExpenseProvider>();
    final accountProvider = context.read<AccountProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final expense = Expense(
      description: template.description,
      amount: template.amount,
      date: DateTime.now(),
      category: template.category,
      paymentMode: 'Other',
      type: template.type,
      accountId: template.accountId,
    );
    final addedId = await expenseProvider.addExpense(expense);
    await accountProvider.refreshBalances();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text('Added ${template.name}'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          await expenseProvider.deleteExpense(addedId);
          await accountProvider.refreshBalances();
        },
      ),
    ));
  }

  List<Widget> get _screens => [
        _DashboardView(
          selectedYear: _selectedYear,
          selectedMonth: _selectedMonth,
          yearView: _yearView,
          onQuickAdd: _quickAddTemplate,
          onRefresh: _refreshDashboard,
          onAddExpense: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddExpenseScreen()),
          ),
          onMonthChanged: (y, m) {
            setState(() {
              _selectedYear = y;
              _selectedMonth = m;
            });
            // Ensure the selected year is loaded
            context.read<ExpenseProvider>().ensureYearLoaded(y);
          },
          onViewToggle: (isYear) {
            setState(() {
              _yearView = isYear;
            });
          },
        ),
        const ExpenseListScreen(),
        const MoreScreen(),
      ];

  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      // SafeArea keeps the sheet's items above the system navigation bar in
      // edge-to-edge mode; without it the last tile is covered and untappable.
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.money_off),
              title: const Text('Add Expense'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AddExpenseScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.trending_up),
              title: const Text('Add Investment'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AddInvestmentScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance Tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'How to use',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TutorialScreen()),
              );
            },
          ),
        ],
      ),
      // IndexedStack keeps every tab mounted, so the Transactions screen's
      // search, filters, and scroll position survive tab switches.
      body: IndexedStack(index: _selectedIndex, children: _screens),
      // Compact circular FAB: an extended (labelled) FAB is wide enough to sit
      // over the trailing amount column on the Transactions tab and hide it.
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddOptions(context),
        tooltip: 'Add transaction',
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Expenses',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            selectedIcon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

class _DashboardView extends StatelessWidget {
  final int selectedYear;
  final int selectedMonth;
  final bool yearView;
  final void Function(int year, int month) onMonthChanged;
  final void Function(bool isYear) onViewToggle;
  final Future<void> Function(TxTemplate template) onQuickAdd;
  final Future<void> Function() onRefresh;
  final VoidCallback onAddExpense;

  const _DashboardView({
    required this.selectedYear,
    required this.selectedMonth,
    required this.yearView,
    required this.onMonthChanged,
    required this.onViewToggle,
    required this.onQuickAdd,
    required this.onRefresh,
    required this.onAddExpense,
  });

  /// Opens the transactions that make up one category's slice for the current
  /// period, so tapping the pie answers "what's actually in this?".
  void _showCategoryDetail(
      BuildContext context, ExpenseProvider provider, String category,
      {required bool isYear}) {
    final rows = (isYear
            ? provider
                .expensesForYear(selectedYear)
                .where((e) => e.isExpense)
            : provider.spendingForMonth(selectedYear, selectedMonth))
        .where((e) => e.category == category)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final total = rows.fold<int>(0, (s, e) => s + provider.baseAmountOf(e));
    final period = isYear
        ? '$selectedYear'
        : '$selectedYear-${selectedMonth.toString().padLeft(2, '0')}';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CategoryDetailSheet(
        category: category,
        period: period,
        total: total,
        rows: rows,
        baseAmountOf: provider.baseAmountOf,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ExpenseProvider>(
      builder: (context, provider, _) {
        final monthlyExpenses =
            provider.spendingForMonth(selectedYear, selectedMonth);
        final yearlyExpenses = provider
            .expensesForYear(selectedYear)
            .where((e) => e.isExpense)
            .toList();
        final monthlyIncome =
            provider.incomeForMonth(selectedYear, selectedMonth);
        final yearlyIncome = provider.incomeForYear(selectedYear);
        // The per-period totals below are read straight from the provider; it
        // memoizes each aggregate until the data changes, so repeated calls in
        // one build (and across the other screens) are free.

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: SingleChildScrollView(
            // AlwaysScrollable so pull-to-refresh works even when the content
            // is short enough not to overflow.
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              // fab: leave room so the last chart/total clears the FAB and the
              // system nav bar instead of being hidden behind them.
              padding: scrollPadding(context, all: 16, fab: true),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const AlertsBanner(),
                  const NetWorthCard(),
                  const _ShortcutsRow(),
                  _QuickAddRow(onQuickAdd: onQuickAdd),
                  MonthSelector(
                    initialYear: selectedYear,
                    initialMonth: selectedMonth,
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
                    onSelectionChanged: (s) => onViewToggle(s.first),
                  ),
                  const SizedBox(height: 16),
                  if (yearView) ...[
                    // Tell "still loading" apart from "nothing recorded"; the
                    // empty text otherwise flashes on every cold start.
                    if (yearlyExpenses.isEmpty && provider.isLoading)
                      const DashboardSkeleton()
                    else if (yearlyExpenses.isEmpty)
                      EmptyState(
                        icon: Icons.savings_outlined,
                        title: 'Nothing recorded in $selectedYear yet',
                        message:
                            'Add a transaction to see your yearly breakdown.',
                        actionLabel: 'Add expense',
                        onAction: onAddExpense,
                      )
                    else ...[
                      _TotalHeadline(
                        label: 'Year total',
                        amount: provider.totalForYear(selectedYear),
                        income: yearlyIncome,
                      ),
                      const SizedBox(height: 16),
                      const SectionHeader('Spending by category (year)'),
                      const SizedBox(height: 4),
                      CategoryBarChart(
                        totals:
                            provider.categoryTotalsForYear(selectedYear),
                        onCategoryTap: (c) => _showCategoryDetail(
                            context, provider, c,
                            isYear: true),
                      ),
                    ],
                  ] else ...[
                    if (monthlyExpenses.isEmpty && provider.isLoading)
                      const DashboardSkeleton()
                    else if (monthlyExpenses.isEmpty)
                      EmptyState(
                        icon: Icons.account_balance_wallet_outlined,
                        title: 'No expenses this month',
                        message:
                            'Track your first expense to see charts and trends.',
                        actionLabel: 'Add expense',
                        onAction: onAddExpense,
                      )
                    else ...[
                      _TotalHeadline(
                        label: 'This month',
                        amount:
                            provider.totalForMonth(selectedYear, selectedMonth),
                        income: monthlyIncome,
                      ),
                      _LeftToSpend(
                        cap: context
                            .watch<BudgetProvider>()
                            .overallBudget(selectedYear, selectedMonth),
                        spent:
                            provider.totalForMonth(selectedYear, selectedMonth),
                      ),
                      const SizedBox(height: 16),
                      const SectionHeader('Spending by category'),
                      const SizedBox(height: 4),
                      CategoryBarChart(
                        totals: provider.categoryTotalsForMonth(
                            selectedYear, selectedMonth),
                        onCategoryTap: (c) => _showCategoryDetail(
                            context, provider, c,
                            isYear: false),
                      ),
                      const SizedBox(height: 16),
                      const SectionHeader('Trends (last 12 months)'),
                      ExpenseTrendsChart(provider: provider),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
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

  const _CategoryDetailSheet({
    required this.category,
    required this.period,
    required this.total,
    required this.rows,
    required this.baseAmountOf,
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
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
              ),
              Text(formatMoney(total),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
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
                        subtitle: Text(formatIsoDate(e.date)),
                        trailing: Text(formatMoney(baseAmountOf(e)),
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Headline total with an animated count-up, plus an optional income line.
class _TotalHeadline extends StatelessWidget {
  final String label;
  final int amount;
  final int income;
  const _TotalHeadline({
    required this.label,
    required this.amount,
    required this.income,
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
        if (income > 0)
          Text(
            'Income ${formatMoney(income)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: incomeColor(context),
            ),
          ),
      ],
    );
  }
}

/// One line under the month total showing how much of the overall monthly
/// budget is left (or how far over it is). Renders nothing when no overall
/// budget is set for the month.
class _LeftToSpend extends StatelessWidget {
  /// Overall cap and spend for the month, in base-currency minor units.
  final int cap;
  final int spent;
  const _LeftToSpend({required this.cap, required this.spent});

  @override
  Widget build(BuildContext context) {
    if (cap <= 0) return const SizedBox.shrink();
    final left = cap - spent;
    final over = left < 0;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        over
            ? 'Over budget by ${formatMoney(-left)}'
            : '${formatMoney(left)} left to spend',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: over ? expenseColor(context) : incomeColor(context),
        ),
      ),
    );
  }
}

/// Quick navigation shortcuts on the dashboard for destinations otherwise a
/// couple of taps away under More: Investments always, and Import from SMS
/// when SMS reading is switched on (so the shortcut never leads to a screen
/// that can only report it is off). Both stay listed under More as well; this
/// is just a faster path from the home screen.
class _ShortcutsRow extends StatelessWidget {
  const _ShortcutsRow();

  @override
  Widget build(BuildContext context) {
    final smsEnabled = context.watch<SettingsProvider>().smsImportEnabled;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: _ShortcutButton(
              icon: Icons.trending_up,
              label: 'Investments',
              // Distinct accents (not one shared container) so the shortcuts
              // read as separate destinations at a glance.
              accent: const Color(0xFF00897B), // teal
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const InvestmentsScreen()),
              ),
            ),
          ),
          if (smsEnabled) ...[
            const SizedBox(width: 8),
            Expanded(
              child: _ShortcutButton(
                icon: Icons.sms,
                label: 'Import SMS',
                accent: const Color(0xFF6A3DE8), // violet
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const SmsReviewScreen()),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One tappable shortcut chip used in [_ShortcutsRow].
class _ShortcutButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  const _ShortcutButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // A soft tint of the accent as fill, the accent itself for icon and text,
    // so each shortcut carries its own color without shouting.
    final fill = accent.withValues(alpha: dark ? 0.24 : 0.14);
    final foreground = dark ? Color.lerp(accent, Colors.white, 0.4)! : accent;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accent.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: foreground),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal row of saved templates for one-tap adding from the dashboard.
class _QuickAddRow extends StatelessWidget {
  final Future<void> Function(TxTemplate template) onQuickAdd;
  const _QuickAddRow({required this.onQuickAdd});

  /// Confirms before dropping a saved quick-add shortcut. Deleting the
  /// template only removes the one-tap shortcut — transactions already added
  /// from it are untouched.
  Future<void> _confirmDelete(
      BuildContext context, TemplateProvider provider, TxTemplate template) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete quick add?'),
        content: Text('Remove "${template.name}" from your quick-add '
            'shortcuts? Transactions you already added are not affected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await provider.deleteTemplate(template.id!);
    messenger.showSnackBar(
      SnackBar(content: Text('Deleted quick add "${template.name}"')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TemplateProvider>(
      builder: (context, provider, _) {
        final templates = provider.templates;
        if (templates.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Quick add', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: templates.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final template = templates[index];
                    // Tap the chip to add; the delete "x" removes the shortcut
                    // (after a confirm), so a quick-add saved by mistake or no
                    // longer used can be cleared.
                    return InputChip(
                      avatar: const Icon(Icons.bolt, size: 18),
                      label: Text(
                          '${template.name} · ${formatMoneyRounded(template.amount)}'),
                      onPressed: () => onQuickAdd(template),
                      onDeleted: template.id == null
                          ? null
                          : () => _confirmDelete(context, provider, template),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      deleteButtonTooltipMessage: 'Delete quick add',
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
