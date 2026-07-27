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
import '../widgets/alerts_banner.dart';
import '../widgets/expense_chart.dart';
import '../widgets/expense_trends_chart.dart';
import '../widgets/month_selector.dart';
import '../widgets/net_worth_card.dart';
import 'add_expense_screen.dart';
import 'add_investment_screen.dart';
import 'expense_list_screen.dart';
import 'more_screen.dart';
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
    final recurringProvider = context.read<RecurringProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final posted = await RecurringService.instance.postDueTransactions();
    if (posted > 0) {
      await expenseProvider.reloadLoadedYears();
      await accountProvider.refreshBalances();
      await recurringProvider.fetchRules();
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text((posted == 1
              ? '1 recurring transaction posted'
              : '$posted recurring transactions posted')),
        ));
      }
    }
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddOptions(context),
        tooltip: 'Add transaction',
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
              icon: const Icon(Icons.list), label: 'Expenses'),
          BottomNavigationBarItem(
              icon: const Icon(Icons.more_horiz), label: 'More'),
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

  const _DashboardView({
    required this.selectedYear,
    required this.selectedMonth,
    required this.yearView,
    required this.onMonthChanged,
    required this.onViewToggle,
    required this.onQuickAdd,
  });

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

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('Dashboard & Charts',
                    style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 12),
                const AlertsBanner(),
                const NetWorthCard(),
                _QuickAddRow(onQuickAdd: onQuickAdd),
                MonthSelector(
                  initialYear: selectedYear,
                  initialMonth: selectedMonth,
                  onChanged: onMonthChanged,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('View:'),
                    const SizedBox(width: 8),
                    ToggleButtons(
                      isSelected: [!yearView, yearView],
                      onPressed: (i) => onViewToggle(i == 1),
                      children: [const Text('Month'), const Text('Year')],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (yearView) ...[
                  // Tell "still loading" apart from "nothing recorded"; the
                  // empty text otherwise flashes on every cold start.
                  if (yearlyExpenses.isEmpty && provider.isLoading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (yearlyExpenses.isEmpty)
                    const Text('No expenses this year.')
                  else ...[
                    SizedBox(
                      height: 250,
                      child: ExpenseChart(
                          totals: provider.categoryTotalsForYear(selectedYear)),
                    ),
                    Text(
                      'Year Total: ${formatMoney(provider.totalForYear(selectedYear))}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if (yearlyIncome > 0)
                      Text(
                        'Income: ${formatMoney(yearlyIncome)}',
                        style: TextStyle(
                            fontSize: 14, color: incomeColor(context)),
                      ),
                    const SizedBox(height: 16),
                    Text('Category Breakdown (Year)',
                        style: const TextStyle(fontSize: 16)),
                    SizedBox(
                      height: 180,
                      child: ListView(
                        shrinkWrap: true,
                        children: provider
                            .categoryTotalsForYear(selectedYear)
                            .entries
                            .map((e) => ListTile(
                                  dense: true,
                                  title: Text(e.key),
                                  trailing: Text(formatMoney(e.value)),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                ] else ...[
                  if (monthlyExpenses.isEmpty && provider.isLoading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (monthlyExpenses.isEmpty)
                    const Text('No expenses this month.')
                  else ...[
                    SizedBox(
                      height: 250,
                      child: ExpenseChart(
                          totals: provider.categoryTotalsForMonth(
                              selectedYear, selectedMonth)),
                    ),
                    Text(
                      'Total: ${formatMoney(provider.totalForMonth(selectedYear, selectedMonth))}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if (monthlyIncome > 0)
                      Text(
                        'Income: ${formatMoney(monthlyIncome)}',
                        style: TextStyle(
                            fontSize: 14, color: incomeColor(context)),
                      ),
                    const SizedBox(height: 16),
                    Text('Trends (Last 12 Months)',
                        style: const TextStyle(fontSize: 16)),
                    ExpenseTrendsChart(provider: provider),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Horizontal row of saved templates for one-tap adding from the dashboard.
class _QuickAddRow extends StatelessWidget {
  final Future<void> Function(TxTemplate template) onQuickAdd;
  const _QuickAddRow({required this.onQuickAdd});

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
                    return ActionChip(
                      avatar: const Icon(Icons.bolt, size: 18),
                      label: Text(
                          '${template.name} · ${formatMoneyRounded(template.amount)}'),
                      onPressed: () => onQuickAdd(template),
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
