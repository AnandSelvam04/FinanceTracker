import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/goal.dart';
import '../providers/goal_provider.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/insets.dart';
import '../widgets/empty_state.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GoalProvider>().fetchGoals();
    });
  }

  /// Compact deadline label, e.g. "Jul 2026".
  String _dateLabel(DateTime d) =>
      '${monthName(d.month).substring(0, 3)} ${d.year}';

  Future<void> _showGoalDialog({Goal? goal}) async {
    final formKey = GlobalKey<FormState>();
    var name = goal?.name ?? '';
    var target = goal?.targetAmount ?? 0;
    var saved = goal?.savedAmount ?? 0;
    DateTime? targetDate = goal?.targetDate;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(goal == null ? 'New Goal' : 'Edit Goal'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: name,
                    decoration: const InputDecoration(
                        labelText: 'Name', hintText: 'e.g. Emergency Fund'),
                    textCapitalization: TextCapitalization.words,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? 'Required'
                            : null,
                    onSaved: (value) => name = value!.trim(),
                  ),
                  TextFormField(
                    initialValue: target == 0 ? '' : minorToEditString(target),
                    decoration: const InputDecoration(labelText: 'Target amount'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: validateAmountField,
                    onSaved: (value) => target = parseMinor(value ?? '0') ?? 0,
                  ),
                  TextFormField(
                    initialValue: saved == 0 ? '' : minorToEditString(saved),
                    decoration: const InputDecoration(
                        labelText: 'Already saved (optional)'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? null
                        : validateAmountField(value, allowZero: true),
                    onSaved: (value) => saved =
                        (value == null || value.trim().isEmpty)
                            ? 0
                            : (parseMinor(value) ?? 0),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(targetDate == null
                            ? 'No target date'
                            : 'By ${_dateLabel(targetDate!)}'),
                      ),
                      if (targetDate != null)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Clear date',
                          onPressed: () =>
                              setDialogState(() => targetDate = null),
                        ),
                      TextButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: targetDate ??
                                DateTime(now.year, now.month + 1, now.day),
                            firstDate: DateTime(now.year - 1),
                            lastDate: DateTime(now.year + 50),
                          );
                          if (picked != null) {
                            setDialogState(() => targetDate = picked);
                          }
                        },
                        child: const Text('Pick date'),
                      ),
                    ],
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
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  formKey.currentState!.save();
                  final provider = context.read<GoalProvider>();
                  final newGoal = Goal(
                    id: goal?.id,
                    name: name,
                    targetAmount: target,
                    savedAmount: saved,
                    targetDate: targetDate,
                  );
                  if (goal == null) {
                    await provider.addGoal(newGoal);
                  } else {
                    await provider.updateGoal(newGoal);
                  }
                  if (context.mounted) Navigator.of(context).pop();
                }
              },
              child: Text(goal == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showContributionDialog(Goal goal) async {
    final formKey = GlobalKey<FormState>();
    var amount = 0;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add to ${goal.name}'),
        content: Form(
          key: formKey,
          child: TextFormField(
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Contribution', hintText: 'Amount to add'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: validateAmountField,
            onSaved: (value) => amount = parseMinor(value ?? '0') ?? 0,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                formKey.currentState!.save();
                await context
                    .read<GoalProvider>()
                    .addContribution(goal, amount);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Goal goal) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete goal?'),
        content: Text('Remove "${goal.name}"? This only deletes the goal, not '
            'any transactions.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && goal.id != null) {
      await context.read<GoalProvider>().deleteGoal(goal.id!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Goals')),
      body: Consumer<GoalProvider>(
        builder: (context, provider, _) {
          final goals = provider.goals;
          if (goals.isEmpty) {
            return EmptyState(
              icon: Icons.savings_outlined,
              title: 'No goals yet',
              message:
                  'Set a savings target — an emergency fund, a trip, a big '
                  'purchase — and track your progress toward it.',
              actionLabel: 'Add goal',
              onAction: () => _showGoalDialog(),
            );
          }
          return ListView.separated(
            itemCount: goals.length + 1,
            padding: scrollPadding(context, all: 12, fab: true),
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _SummaryCard(
                  saved: provider.totalSaved,
                  target: provider.totalTarget,
                );
              }
              return _GoalCard(
                goal: goals[index - 1],
                dateLabel: _dateLabel,
                onContribute: _showContributionDialog,
                onEdit: (g) => _showGoalDialog(goal: g),
                onDelete: _confirmDelete,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add goal',
        onPressed: () => _showGoalDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Roll-up of saved vs. combined target across all goals.
class _SummaryCard extends StatelessWidget {
  final int saved;
  final int target;
  const _SummaryCard({required this.saved, required this.target});

  @override
  Widget build(BuildContext context) {
    final ratio = target <= 0 ? 0.0 : (saved / target).clamp(0.0, 1.0);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('All goals',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    )),
            const SizedBox(height: 6),
            Text('${formatMoney(saved)} of ${formatMoney(target)} saved',
                style: TextStyle(color: mutedTextColor(context))),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio.toDouble(),
                minHeight: 8,
                color: incomeColor(context),
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

class _GoalCard extends StatelessWidget {
  final Goal goal;
  final String Function(DateTime) dateLabel;
  final Future<void> Function(Goal) onContribute;
  final Future<void> Function(Goal) onEdit;
  final Future<void> Function(Goal) onDelete;

  const _GoalCard({
    required this.goal,
    required this.dateLabel,
    required this.onContribute,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final complete = goal.isComplete;
    final barColor = complete ? incomeColor(context) : Colors.blue;
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
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          goal.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (complete)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(Icons.check_circle,
                              size: 18, color: incomeColor(context)),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'edit':
                        onEdit(goal);
                      case 'delete':
                        onDelete(goal);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            Text(
              '${formatMoney(goal.savedAmount)} of ${formatMoney(goal.targetAmount)}',
              style: TextStyle(color: mutedTextColor(context)),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: goal.progress,
                minHeight: 8,
                color: barColor,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  complete
                      ? 'Goal reached 🎉'
                      : '${formatMoney(goal.remaining)} to go',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: complete ? incomeColor(context) : null,
                  ),
                ),
                if (goal.targetDate != null) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.event,
                      size: 14, color: mutedTextColor(context)),
                  const SizedBox(width: 2),
                  Text(
                    dateLabel(goal.targetDate!),
                    style: TextStyle(
                        fontSize: 13, color: mutedTextColor(context)),
                  ),
                ],
                const Spacer(),
                TextButton.icon(
                  onPressed: () => onContribute(goal),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
