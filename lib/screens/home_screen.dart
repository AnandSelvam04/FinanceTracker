import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/expense.dart';
import '../models/tx_template.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/investment_provider.dart';
import '../providers/recurring_provider.dart';
import '../providers/template_provider.dart';
import '../services/recurring_service.dart';
import '../widgets/expense_chart.dart';
import '../widgets/expense_trends_chart.dart';
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
      context.read<RecurringProvider>().fetchRules();
      await _postRecurring();
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
          content: Text(
              'Posted $posted recurring transaction${posted == 1 ? '' : 's'}'),
        ));
      }
    }
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
    await expenseProvider.addExpense(expense);
    await accountProvider.refreshBalances();
    final added = expenseProvider.expenses.firstWhere(
      (e) =>
          e.description == expense.description &&
          e.amount == expense.amount &&
          e.date.year == expense.date.year &&
          e.date.month == expense.date.month &&
          e.date.day == expense.date.day,
      orElse: () => expense,
    );
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text('Added ${template.name}'),
      action: added.id == null
          ? null
          : SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                await expenseProvider.deleteExpense(added.id!);
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
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.money_off),
            title: const Text('Add Expense'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddExpenseScreen()),
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
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TutorialScreen()),
              );
            },
          ),
        ],
      ),
      body: _screens[_selectedIndex],
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddOptions(context),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Expenses'),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'More'),
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
                const Text('Dashboard & Charts',
                    style: TextStyle(fontSize: 20)),
                const SizedBox(height: 12),
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
                      children: const [Text('Month'), Text('Year')],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (yearView) ...[
                  if (yearlyExpenses.isEmpty)
                    const Text('No expenses this year.')
                  else ...[
                    SizedBox(
                      height: 250,
                      child: ExpenseChart(expenses: yearlyExpenses),
                    ),
                    Text(
                      'Year Total: ₹${provider.totalForYear(selectedYear).toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if (yearlyIncome > 0)
                      Text(
                        'Income: ₹${yearlyIncome.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 14, color: Colors.green.shade700),
                      ),
                    const SizedBox(height: 16),
                    const Text('Category Breakdown (Year)',
                        style: TextStyle(fontSize: 16)),
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
                                  trailing:
                                      Text('₹${e.value.toStringAsFixed(2)}'),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                ] else ...[
                  if (monthlyExpenses.isEmpty)
                    const Text('No expenses this month.')
                  else ...[
                    SizedBox(
                      height: 250,
                      child: ExpenseChart(expenses: monthlyExpenses),
                    ),
                    Text(
                      'Total: ₹${provider.totalForMonth(selectedYear, selectedMonth).toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if (monthlyIncome > 0)
                      Text(
                        'Income: ₹${monthlyIncome.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 14, color: Colors.green.shade700),
                      ),
                    const SizedBox(height: 16),
                    const Text('Trends (Last 12 Months)',
                        style: TextStyle(fontSize: 16)),
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
              const Text('Quick add', style: TextStyle(fontSize: 13)),
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
                          '${template.name} · ₹${template.amount.toStringAsFixed(0)}'),
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

class MonthSelector extends StatefulWidget {
  final void Function(int year, int month) onChanged;
  final int initialYear;
  final int initialMonth;
  const MonthSelector({
    super.key,
    required this.onChanged,
    required this.initialYear,
    required this.initialMonth,
  });

  @override
  State<MonthSelector> createState() => _MonthSelectorState();
}

class _MonthSelectorState extends State<MonthSelector> {
  late int year;
  late int month;

  @override
  void initState() {
    super.initState();
    year = widget.initialYear;
    month = widget.initialMonth;
  }

  void _changeMonth(int delta) {
    setState(() {
      month += delta;
      if (month > 12) {
        month = 1;
        year++;
      } else if (month < 1) {
        month = 12;
        year--;
      }
      widget.onChanged(year, month);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _changeMonth(-1),
        ),
        Text(
          '$year-${month.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 16),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () => _changeMonth(1),
        ),
      ],
    );
  }
}
