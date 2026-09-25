import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/budget.dart';
import '../providers/budget_provider.dart';
import '../providers/expense_provider.dart';
import '../services/db_service.dart';
import '../utils/alerts.dart';
import '../utils/app_colors.dart';
import '../utils/category_suggestions.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/db_constants.dart';
import '../utils/insets.dart';
import '../widgets/category_choice_chip.dart';
import '../widgets/category_avatar.dart';
import '../widgets/empty_state.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  final _formKey = GlobalKey<FormState>();
  String _category = '';
  int _amount = 0; // minor units
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;

  /// The month the screen is showing. Budgets are per month, so listing every
  /// month's caps at once (as this screen used to) buried this month's among
  /// stale ones; a stepper keeps one month in view at a time.
  int _viewYear = DateTime.now().year;
  int _viewMonth = DateTime.now().month;

  bool get _viewingCurrentMonth {
    final now = DateTime.now();
    return _viewYear == now.year && _viewMonth == now.month;
  }

  Future<void> _stepMonth(int delta) async {
    final target = DateTime(_viewYear, _viewMonth + delta);
    setState(() {
      _viewYear = target.year;
      _viewMonth = target.month;
    });
    // Spend for a year outside the loaded set would read as zero otherwise.
    await context.read<ExpenseProvider>().ensureYearLoaded(target.year);
  }

  /// Common expense categories offered in the picker before the user has any
  /// spend history — kept in step with the Add Expense screen's defaults.
  static const List<String> _defaultCategories = [
    'Food',
    'Transport',
    'Shopping',
    'Bills',
    'Entertainment',
    'Health',
    'Education',
    'Other',
  ];

  /// Real category spellings to suggest in the budget dialog, so a cap matches
  /// the spend it tracks. Filled from actual usage in [initState].
  List<String> _categorySuggestions = _defaultCategories;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final budgetProvider = context.read<BudgetProvider>();
      final expenseProvider = context.read<ExpenseProvider>();
      await budgetProvider.fetchBudgets();
      // Load every year a budget references (plus this year, for the overall
      // cap's spend) so "Spent" is accurate.
      final years = {
        DateTime.now().year,
        ...budgetProvider.budgets.map((b) => b.year),
      };
      for (final year in years) {
        await expenseProvider.ensureYearLoaded(year);
      }
      // Prefer the exact category spellings already on transactions and
      // budgets, so a chosen cap lines up with the spend it should track.
      final frequent =
          await DBService().frequentCategories(DbConstants.txExpense);
      if (!mounted) return;
      setState(() {
        _categorySuggestions = budgetCategorySuggestions(
          used: [
            ...frequent,
            ...budgetProvider.categoryBudgets.map((b) => b.category),
          ],
          defaults: _defaultCategories,
        );
      });
    });
  }

  Future<void> _showBudgetDialog({Budget? budget}) async {
    if (budget != null) {
      _category = budget.category;
      _amount = budget.amount;
      _year = budget.year;
      _month = budget.month;
    } else {
      _category = '';
      _amount = 0;
      // New budgets default to the month on screen, not always "now".
      _year = _viewYear;
      _month = _viewMonth;
    }

    final categoryController = TextEditingController(text: _category);
    var selectedYear = _year;
    var selectedMonth = _month;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(budget == null ? 'Add Budget' : 'Edit Budget'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Category field plus quick-pick chips. Picking a chip fills the
                // field with the exact spelling used on transactions, so the cap
                // matches the spend it tracks. StatefulBuilder rebuilds just this
                // block so the selected chip highlights without a full setState.
                StatefulBuilder(
                  builder: (context, setFieldState) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: categoryController,
                          decoration:
                              const InputDecoration(labelText: 'Category'),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                          onChanged: (_) => setFieldState(() {}),
                        ),
                        if (_categorySuggestions.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: _categorySuggestions
                                .map((c) => CategoryChoiceChip(
                                      category: c,
                                      selected: isSameCategory(
                                          categoryController.text, c),
                                      onSelected: () => setFieldState(
                                          () => categoryController.text = c),
                                    ))
                                .toList(),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                TextFormField(
                  initialValue: _amount == 0 ? '' : minorToEditString(_amount),
                  decoration: const InputDecoration(labelText: 'Amount'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  // A zero cap silently never alerts (see budgetAlerts), so a
                  // budget has to be a positive amount.
                  validator: validateAmountField,
                  onSaved: (value) => _amount = parseMinor(value ?? '0') ?? 0,
                ),
                const SizedBox(height: 8),
                // Month/year pickers instead of free-typed numbers: no invalid
                // input to validate, and the month reads as a name.
                StatefulBuilder(
                  builder: (context, setFieldState) {
                    final now = DateTime.now();
                    final years = <int>{
                      for (var y = now.year - 5; y <= now.year + 1; y++) y,
                      selectedYear,
                    }.toList()
                      ..sort();
                    return Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedMonth,
                            decoration:
                                const InputDecoration(labelText: 'Month'),
                            items: [
                              for (var m = 1; m <= 12; m++)
                                DropdownMenuItem(
                                    value: m, child: Text(monthName(m))),
                            ],
                            onChanged: (value) => setFieldState(
                                () => selectedMonth = value ?? selectedMonth),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedYear,
                            decoration:
                                const InputDecoration(labelText: 'Year'),
                            items: [
                              for (final y in years)
                                DropdownMenuItem(
                                    value: y, child: Text(y.toString())),
                            ],
                            onChanged: (value) => setFieldState(
                                () => selectedYear = value ?? selectedYear),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (_formKey.currentState!.validate()) {
                _formKey.currentState!.save();
                _category = categoryController.text.trim();
                _year = selectedYear;
                _month = selectedMonth;
                final newBudget = Budget(
                  id: budget?.id,
                  category: _category,
                  amount: _amount,
                  year: _year,
                  month: _month,
                );
                if (budget == null) {
                  await context.read<BudgetProvider>().addBudget(newBudget);
                } else {
                  await context.read<BudgetProvider>().updateBudget(newBudget);
                }
                if (context.mounted) Navigator.of(context).pop();
              }
            },
            child: Text(budget == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
    categoryController.dispose();
  }

  /// Sets or edits the single overall cap for the viewed month (amount only —
  /// it applies to that month across every category).
  Future<void> _showOverallDialog({Budget? existing}) async {
    final year = _viewYear;
    final month = _viewMonth;
    final controller = TextEditingController(
        text: existing == null ? '' : minorToEditString(existing.amount));
    final formKey = GlobalKey<FormState>();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null
            ? 'Set total monthly budget'
            : 'Edit total monthly budget'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration:
                InputDecoration(labelText: 'Cap for ${monthName(month)} $year'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: validateAmountField,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final provider = context.read<BudgetProvider>();
              final budget = Budget(
                id: existing?.id,
                category: Budget.overallCategory,
                amount: parseMinor(controller.text.trim()) ?? 0,
                year: year,
                month: month,
              );
              if (existing == null) {
                await provider.addBudget(budget);
              } else {
                await provider.updateBudget(budget);
              }
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(existing == null ? 'Set' : 'Save'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _confirmDeleteBudget(int id, String label) async {
    final provider = context.read<BudgetProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete budget?'),
        content: Text('Remove the $label budget? This only removes the cap; '
            'your transactions are unaffected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await provider.deleteBudget(id);
  }

  Future<void> _copyLastMonth() async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<BudgetProvider>();
    final copied =
        await provider.copyBudgetsFromPreviousMonth(_viewYear, _viewMonth);
    messenger.showSnackBar(SnackBar(
      content: Text(copied == 0
          ? 'Nothing to copy — no budgets from the previous month are missing '
              'in ${monthName(_viewMonth)}.'
          : 'Copied $copied budget${copied == 1 ? '' : 's'} from the '
              'previous month.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: 'Copy previous month\'s budgets',
            onPressed: _copyLastMonth,
          ),
        ],
      ),
      body: Consumer2<BudgetProvider, ExpenseProvider>(
        builder: (context, budgetProvider, expenseProvider, _) {
          final now = DateTime.now();
          final categoryBudgets = budgetProvider.categoryBudgets
              .where((b) => b.year == _viewYear && b.month == _viewMonth)
              .toList()
            // Most-strained first, so the caps that need attention lead.
            ..sort((a, b) {
              double ratio(Budget x) => x.amount <= 0
                  ? 0
                  : expenseProvider.spentForCategoryInMonth(
                          x.year, x.month, x.category) /
                      x.amount;
              return ratio(b).compareTo(ratio(a));
            });
          final overall =
              budgetProvider.overallBudgetRow(_viewYear, _viewMonth);

          // Thresholds come from alerts.dart so the bar turns red at exactly
          // the point the banner and notifications fire.
          Color progressColor(double ratio) {
            if (ratio >= kBudgetWarnRatio) return expenseColor(context);
            if (ratio >= kBudgetCautionRatio) return warningColor(context);
            return incomeColor(context);
          }

          // Base-currency spend for the cap's category, matched leniently on
          // case/whitespace (see spentForCategoryInMonth) so a budget still
          // tracks spend even if the category was filed with a different case.
          int spentForBudget(Budget b) => expenseProvider
              .spentForCategoryInMonth(b.year, b.month, b.category);

          return ListView(
            padding: scrollPadding(context, all: 12, fab: true),
            children: [
              _BudgetMonthStepper(
                year: _viewYear,
                month: _viewMonth,
                isCurrent: _viewingCurrentMonth,
                onStep: _stepMonth,
                onToday: _viewingCurrentMonth
                    ? null
                    : () => _stepMonth(
                        (now.year - _viewYear) * 12 + now.month - _viewMonth),
              ),
              const SizedBox(height: 8),
              _OverallBudgetCard(
                year: _viewYear,
                month: _viewMonth,
                cap: overall?.amount ?? 0,
                spent: expenseProvider.totalForMonth(_viewYear, _viewMonth),
                now: now,
                progressColor: progressColor,
                onSet: () => _showOverallDialog(existing: overall),
                onClear: overall == null
                    ? null
                    : () => _confirmDeleteBudget(overall.id!, 'total monthly'),
              ),
              const SizedBox(height: 16),
              if (categoryBudgets.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: EmptyState(
                    icon: Icons.pie_chart_outline,
                    title: 'No category budgets for '
                        '${monthName(_viewMonth)}',
                    message: 'Cap a category to track its spending, or copy '
                        'the previous month\'s caps.',
                    actionLabel: 'Add budget',
                    onAction: () => _showBudgetDialog(),
                  ),
                )
              else
                for (final budget in categoryBudgets) ...[
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: CategoryAvatar(category: budget.category),
                      title: Text(budget.category,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Builder(builder: (context) {
                        final spent = spentForBudget(budget);
                        final progress =
                            budget.amount == 0 ? 0.0 : spent / budget.amount;
                        final pace = budgetPace(
                          spent: spent,
                          cap: budget.amount,
                          year: budget.year,
                          month: budget.month,
                          now: now,
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${formatMoney(spent)} of '
                                '${formatMoneyRounded(budget.amount)}'),
                            if (pace != null)
                              _PaceLine(pace: pace, compact: true),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: progress.clamp(0.0, 1.0).toDouble(),
                              color: progressColor(progress),
                            ),
                          ],
                        );
                      }),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            tooltip: 'Edit budget',
                            onPressed: () => _showBudgetDialog(budget: budget),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            tooltip: 'Delete budget',
                            onPressed: () => _confirmDeleteBudget(
                                budget.id!, budget.category),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add Budget',
        onPressed: () => _showBudgetDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// The overall monthly cap card at the top of the Budgets screen: total spent
/// against the cap, how much is left, and a set/edit entry point. Doubles as
/// the empty state when no overall budget is set yet.
class _OverallBudgetCard extends StatelessWidget {
  final int year;
  final int month;

  /// Cap and spend for the month, in base-currency minor units. cap == 0 means
  /// no overall budget is set.
  final int cap;
  final int spent;

  /// Today, for the month-end pace forecast (only shown for the current month).
  final DateTime now;
  final Color Function(double ratio) progressColor;
  final VoidCallback onSet;

  /// Null when there's nothing to clear (no overall budget set).
  final VoidCallback? onClear;

  const _OverallBudgetCard({
    required this.year,
    required this.month,
    required this.cap,
    required this.spent,
    required this.now,
    required this.progressColor,
    required this.onSet,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final label = '${monthName(month)} $year';
    if (cap <= 0) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.savings_outlined),
          title: const Text('Total monthly budget'),
          subtitle: Text('Set one cap for all spending in $label. '
              'Spent so far: ${formatMoney(spent)}.'),
          trailing: TextButton(onPressed: onSet, child: const Text('Set')),
        ),
      );
    }
    final left = cap - spent;
    final ratio = spent / cap;
    final pace =
        budgetPace(spent: spent, cap: cap, year: year, month: month, now: now);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // The month is already in the stepper right above this card,
                // and repeating it here wrapped the title onto two lines.
                Expanded(
                  child: Text('Total monthly budget',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: 'Edit total budget',
                  onPressed: onSet,
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  tooltip: 'Remove total budget',
                  onPressed: onClear,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${formatMoney(spent)} of ${formatMoneyRounded(cap)}'),
                Text(
                  left >= 0
                      ? '${formatMoney(left)} left'
                      : '${formatMoney(-left)} over',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: progressColor(ratio),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0).toDouble(),
              minHeight: 10,
              color: progressColor(ratio),
            ),
            if (pace != null) ...[
              const SizedBox(height: 8),
              _PaceLine(pace: pace),
            ],
          ],
        ),
      ),
    );
  }
}

/// Month stepper for the Budgets screen, with a jump back to the current month
/// when viewing another one.
class _BudgetMonthStepper extends StatelessWidget {
  final int year;
  final int month;
  final bool isCurrent;
  final ValueChanged<int> onStep;
  final VoidCallback? onToday;

  const _BudgetMonthStepper({
    required this.year,
    required this.month,
    required this.isCurrent,
    required this.onStep,
    required this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous month',
          onPressed: () => onStep(-1),
        ),
        Expanded(
          child: Column(
            children: [
              Text('${monthName(month)} $year',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              if (isCurrent)
                Text('This month',
                    style: TextStyle(
                        fontSize: 12, color: mutedTextColor(context))),
            ],
          ),
        ),
        if (onToday != null)
          TextButton(onPressed: onToday, child: const Text('Today')),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next month',
          onPressed: () => onStep(1),
        ),
      ],
    );
  }
}

/// One-line month-end forecast under a budget's progress bar: a warning when
/// the current pace breaks the cap before it is actually broken, otherwise
/// how much can still be spent per day.
class _PaceLine extends StatelessWidget {
  final BudgetPace pace;

  /// Shorter wording for the per-category rows.
  final bool compact;

  const _PaceLine({required this.pace, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    final String text;
    if (pace.spent > pace.cap) {
      // Already over: the progress bar says so; the pace adds nothing.
      return const SizedBox.shrink();
    } else if (pace.onTrackToOverspend) {
      icon = Icons.trending_up;
      color = warningColor(context);
      text = compact
          ? 'On pace for ${formatMoneyRounded(pace.projected)}'
          : 'On pace for ${formatMoneyRounded(pace.projected)} by month end '
              '— ${formatMoneyRounded(pace.projected - pace.cap)} over';
    } else {
      icon = Icons.check_circle_outline;
      color = incomeColor(context);
      text = pace.daysLeft == 0
          ? '${formatMoneyRounded(pace.dailyAllowance)} left today'
          : '${formatMoneyRounded(pace.dailyAllowance)}/day for '
              '${pace.daysLeft + 1} days';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
