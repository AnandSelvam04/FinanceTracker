import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/budget.dart';
import '../providers/budget_provider.dart';
import '../providers/expense_provider.dart';
import '../utils/currency_format.dart';
import '../utils/insets.dart';

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
      // Load every year a budget references so "Spent" is accurate.
      final years = budgetProvider.budgets.map((b) => b.year).toSet();
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
                keyboardType: TextInputType.number,
                validator: (value) {
                  final parsed = double.tryParse(value ?? '');
                  return parsed == null ? 'Invalid number' : null;
                },
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: Consumer2<BudgetProvider, ExpenseProvider>(
        builder: (context, budgetProvider, expenseProvider, _) {
          final budgets = budgetProvider.budgets;
          if (budgets.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined,
                        size: 48, color: Colors.grey),
                    const SizedBox(height: 8),
                    const Text('No budgets yet. Add one to start tracking.'),
                  ],
                ),
              ),
            );
          }

          Color progressColor(double ratio) {
            if (ratio >= 0.9) return Colors.red;
            if (ratio >= 0.7) return Colors.orange;
            return Colors.green;
          }

          int spentForBudget(Budget b) {
            return expenseProvider
                .spendingForMonth(b.year, b.month)
                .where((e) => e.category == b.category)
                .fold(0, (sum, e) => sum + e.amount);
          }

          return ListView.separated(
            itemCount: budgets.length,
            padding: scrollPadding(context, all: 12, fab: true),
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final budget = budgets[index];
              final spent = spentForBudget(budget);
              final progress = budget.amount == 0 ? 0.0 : spent / budget.amount;
              return Card(
                elevation: 2,
                child: ListTile(
                  title: Text(
                      '${budget.category} · ${budget.year}/${budget.month.toString().padLeft(2, '0')}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Budget: ${formatMoneyRounded(budget.amount)}'),
                      Text('Spent: ${formatMoney(spent)}'),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0).toDouble(),
                        color: progressColor(progress),
                        backgroundColor: Colors.grey.shade200,
                      ),
                    ],
                  ),
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
                        onPressed: () =>
                            budgetProvider.deleteBudget(budget.id!),
                      ),
                    ],
                  ),
                ),
              );
            },
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
