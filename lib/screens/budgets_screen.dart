import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/budget.dart';
import '../providers/budget_provider.dart';
import '../providers/expense_provider.dart';
import '../utils/alerts.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/insets.dart';
import '../widgets/category_avatar.dart';

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
      _year = DateTime.now().year;
      _month = DateTime.now().month;
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(budget == null ? 'Add Budget' : 'Edit Budget'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                validator: (value) =>
                    (value == null || value.isEmpty) ? 'Required' : null,
                onSaved: (value) => _category = value ?? '',
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
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      decoration: const InputDecoration(labelText: 'Year'),
                      keyboardType: TextInputType.number,
                      initialValue: _year.toString(),
                      validator: (value) {
                        final parsed = int.tryParse(value ?? '');
                        return parsed == null ? 'Invalid year' : null;
                      },
                      onSaved: (value) => _year =
                          int.tryParse(value ?? '${DateTime.now().year}') ??
                              _year,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      decoration: const InputDecoration(labelText: 'Month'),
                      keyboardType: TextInputType.number,
                      initialValue: _month.toString(),
                      validator: (value) {
                        final parsed = int.tryParse(value ?? '');
                        if (parsed == null || parsed < 1 || parsed > 12) {
                          return 'Invalid month';
                        }
                        return null;
                      },
                      onSaved: (value) => _month =
                          int.tryParse(value ?? '${DateTime.now().month}') ??
                              _month,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_formKey.currentState!.validate()) {
                _formKey.currentState!.save();
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
  }

  /// Sets or edits the single overall cap for the current month (amount only —
  /// it always applies to this month across every category).
  Future<void> _showOverallDialog({Budget? existing}) async {
    final now = DateTime.now();
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
            decoration: InputDecoration(
                labelText:
                    'Cap for ${now.year}/${now.month.toString().padLeft(2, '0')}'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: validateAmountField,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final provider = context.read<BudgetProvider>();
              final budget = Budget(
                id: existing?.id,
                category: Budget.overallCategory,
                amount: parseMinor(controller.text.trim()) ?? 0,
                year: now.year,
                month: now.month,
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
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await provider.deleteBudget(id);
  }

  Future<void> _copyLastMonth() async {
    final now = DateTime.now();
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<BudgetProvider>();
    final copied =
        await provider.copyBudgetsFromPreviousMonth(now.year, now.month);
    messenger.showSnackBar(SnackBar(
      content: Text(copied == 0
          ? 'Nothing to copy — last month has no budgets this month is missing.'
          : 'Copied $copied budget${copied == 1 ? '' : 's'} from last month.'),
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
            tooltip: 'Copy last month\'s budgets',
            onPressed: _copyLastMonth,
          ),
        ],
      ),
      body: Consumer2<BudgetProvider, ExpenseProvider>(
        builder: (context, budgetProvider, expenseProvider, _) {
          final now = DateTime.now();
          final categoryBudgets = budgetProvider.categoryBudgets;
          final overall = budgetProvider.overallBudgetRow(now.year, now.month);

          // Thresholds come from alerts.dart so the bar turns red at exactly
          // the point the banner and notifications fire.
          Color progressColor(double ratio) {
            if (ratio >= kBudgetWarnRatio) return expenseColor(context);
            if (ratio >= kBudgetCautionRatio) return Colors.orange;
            return incomeColor(context);
          }

          // baseAmountOf, not e.amount: spending on a foreign-currency account
          // is stored in that account's currency, and the budget cap is in the
          // base currency.
          int spentForBudget(Budget b) {
            return expenseProvider
                .spendingForMonth(b.year, b.month)
                .where((e) => e.category == b.category)
                .fold(0, (sum, e) => sum + expenseProvider.baseAmountOf(e));
          }

          return ListView(
            padding: scrollPadding(context, all: 12, fab: true),
            children: [
              _OverallBudgetCard(
                year: now.year,
                month: now.month,
                cap: overall?.amount ?? 0,
                spent: expenseProvider.totalForMonth(now.year, now.month),
                progressColor: progressColor,
                onSet: () => _showOverallDialog(existing: overall),
                onClear: overall == null
                    ? null
                    : () => _confirmDeleteBudget(
                        overall.id!, 'total monthly'),
              ),
              const SizedBox(height: 16),
              if (categoryBudgets.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No per-category budgets yet.\nTap + to cap a category.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                for (final budget in categoryBudgets) ...[
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: CategoryAvatar(category: budget.category),
                      title: Text(
                          '${budget.category} · ${budget.year}/${budget.month.toString().padLeft(2, '0')}'),
                      subtitle: Builder(builder: (context) {
                        final spent = spentForBudget(budget);
                        final progress =
                            budget.amount == 0 ? 0.0 : spent / budget.amount;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Budget: ${formatMoneyRounded(budget.amount)}'),
                            Text('Spent: ${formatMoney(spent)}'),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: progress.clamp(0.0, 1.0).toDouble(),
                                minHeight: 8,
                                color: progressColor(progress),
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                              ),
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
  final Color Function(double ratio) progressColor;
  final VoidCallback onSet;

  /// Null when there's nothing to clear (no overall budget set).
  final VoidCallback? onClear;

  const _OverallBudgetCard({
    required this.year,
    required this.month,
    required this.cap,
    required this.spent,
    required this.progressColor,
    required this.onSet,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final label = '$year/${month.toString().padLeft(2, '0')}';
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
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Total monthly budget · $label',
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
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0).toDouble(),
                minHeight: 10,
                color: progressColor(ratio),
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
