import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/savings_goal.dart';
import '../providers/goal_provider.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/insets.dart';
import '../widgets/empty_state.dart';
import '../widgets/dispose_with_route.dart';

/// Ring colors offered when creating a goal. Mid-tone shades that read on
/// both light and dark surfaces.
const List<Color> _goalColors = [
  Color(0xFF4B3FE4),
  Color(0xFF00897B),
  Color(0xFFEF6C00),
  Color(0xFFD81B60),
  Color(0xFF1E88E5),
  Color(0xFF7CB342),
];

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<GoalProvider>().fetchGoals());
  }

  Future<void> _showGoalDialog({SavingsGoal? goal}) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: goal?.name ?? '');
    final targetController = TextEditingController(
        text: goal == null ? '' : minorToEditString(goal.target));
    final savedController = TextEditingController(
        text: goal == null || goal.saved == 0
            ? ''
            : minorToEditString(goal.saved));
    var targetDate = goal?.targetDate;
    var color = goal?.color ?? _goalColors.first.toARGB32();

    await showDialog(
      context: context,
      builder: (context) => DisposeWithRoute(
        notifiers: [nameController, targetController, savedController],
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(goal == null ? 'New savings goal' : 'Edit goal'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: nameController,
                      autofocus: goal == null,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                          labelText: 'Goal', hintText: 'e.g. Emergency fund'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    TextFormField(
                      controller: targetController,
                      decoration:
                          const InputDecoration(labelText: 'Target amount'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: validateAmountField,
                    ),
                    TextFormField(
                      controller: savedController,
                      decoration: const InputDecoration(
                          labelText: 'Already saved (optional)'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? null
                          : validateAmountField(v, allowZero: true),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            targetDate == null
                                ? 'No target date'
                                : 'By ${formatShortDate(targetDate!)}',
                          ),
                        ),
                        if (targetDate != null)
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            tooltip: 'Clear target date',
                            onPressed: () =>
                                setDialogState(() => targetDate = null),
                          ),
                        TextButton.icon(
                          icon: const Icon(Icons.event, size: 18),
                          label:
                              Text(targetDate == null ? 'Set date' : 'Change'),
                          onPressed: () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: targetDate ??
                                  DateTime(now.year + 1, now.month, now.day),
                              firstDate: DateTime(now.year, now.month, now.day),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setDialogState(() => targetDate = picked);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      children: [
                        for (final c in _goalColors)
                          Semantics(
                            button: true,
                            selected: c.toARGB32() == color,
                            label: 'Goal color',
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () =>
                                  setDialogState(() => color = c.toARGB32()),
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: c,
                                child: c.toARGB32() == color
                                    ? const Icon(Icons.check,
                                        size: 16, color: Colors.white)
                                    : null,
                              ),
                            ),
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
              FilledButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  final provider = context.read<GoalProvider>();
                  final saved = parseMinor(savedController.text.trim()) ?? 0;
                  final updated = SavingsGoal(
                    id: goal?.id,
                    name: nameController.text.trim(),
                    target: parseMinor(targetController.text.trim()) ?? 0,
                    saved: saved < 0 ? 0 : saved,
                    targetDate: targetDate,
                    color: color,
                  );
                  if (goal == null) {
                    await provider.addGoal(updated);
                  } else {
                    await provider.updateGoal(updated);
                  }
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: Text(goal == null ? 'Create' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Adds to (or, with [withdraw], takes from) a goal's saved amount, then
  /// offers an undo — a mistyped contribution is otherwise a manual fix.
  Future<void> _showContributionDialog(SavingsGoal goal,
      {bool withdraw = false}) async {
    final formKey = GlobalKey<FormState>();
    final controller = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      builder: (context) => DisposeWithRoute(
        notifiers: [controller],
        child: AlertDialog(
          title: Text(
              withdraw ? 'Withdraw from ${goal.name}' : 'Add to ${goal.name}'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Amount',
                helperText: withdraw
                    ? 'Saved so far: ${formatMoney(goal.saved)}'
                    : goal.remaining > 0
                        ? '${formatMoney(goal.remaining)} to go'
                        : null,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final base = validateAmountField(v);
                if (base != null) return base;
                if (withdraw && (parseMinor(v!.trim()) ?? 0) > goal.saved) {
                  return 'More than is saved';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.of(context)
                    .pop(parseMinor(controller.text.trim()) ?? 0);
              },
              child: Text(withdraw ? 'Withdraw' : 'Add'),
            ),
          ],
        ),
      ),
    );
    if (amount == null || amount <= 0 || !mounted) return;

    final provider = context.read<GoalProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final delta = withdraw ? -amount : amount;
    final updated = await provider.contribute(goal, delta);
    final reached = !goal.isComplete && updated.isComplete;
    messenger.showSnackBar(SnackBar(
      content: Text(reached
          ? '🎉 ${goal.name} reached!'
          : withdraw
              ? 'Withdrew ${formatMoney(amount)} from ${goal.name}'
              : 'Added ${formatMoney(amount)} to ${goal.name}'),
      action: SnackBarAction(
        label: 'Undo',
        // Restores the exact prior amount rather than reversing the delta, so
        // a clamped withdrawal undoes cleanly too.
        onPressed: () =>
            provider.updateGoal(updated.copyWith(saved: goal.saved)),
      ),
    ));
  }

  Future<void> _confirmDelete(SavingsGoal goal) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete goal?'),
        content: Text('Remove "${goal.name}"? Your accounts and transactions '
            'are unaffected.'),
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
    if (ok == true && mounted) {
      await context.read<GoalProvider>().deleteGoal(goal.id!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Savings Goals')),
      body: Consumer<GoalProvider>(
        builder: (context, provider, _) {
          final goals = provider.goals;
          if (goals.isEmpty) {
            return EmptyState(
              icon: Icons.flag_outlined,
              title: 'No savings goals yet',
              message: 'Set a target — an emergency fund, a trip, a new '
                  'phone — and track how close you are.',
              actionLabel: 'Create a goal',
              onAction: () => _showGoalDialog(),
            );
          }
          final now = DateTime.now();
          return ListView(
            padding: scrollPadding(context, all: 12, fab: true),
            children: [
              _GoalsSummary(
                saved: provider.totalSaved,
                target: provider.totalTarget,
                count: goals.length,
                reached: goals.where((g) => g.isComplete).length,
              ),
              const SizedBox(height: 12),
              for (final goal in goals) ...[
                _GoalCard(
                  goal: goal,
                  now: now,
                  onAdd: () => _showContributionDialog(goal),
                  onWithdraw: goal.saved > 0
                      ? () => _showContributionDialog(goal, withdraw: true)
                      : null,
                  onEdit: () => _showGoalDialog(goal: goal),
                  onDelete: () => _confirmDelete(goal),
                ),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showGoalDialog(),
        icon: const Icon(Icons.add),
        label: const Text('New goal'),
      ),
    );
  }
}

/// Hero card over the goals list: everything saved toward every goal.
class _GoalsSummary extends StatelessWidget {
  final int saved;
  final int target;
  final int count;
  final int reached;

  const _GoalsSummary({
    required this.saved,
    required this.target,
    required this.count,
    required this.reached,
  });

  @override
  Widget build(BuildContext context) {
    final fg = onBrandGradient(context);
    final ratio = target <= 0 ? 0.0 : (saved / target).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: brandGradient(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Saved toward goals',
              style: TextStyle(color: fg.withValues(alpha: 0.85))),
          const SizedBox(height: 4),
          Text(formatMoney(saved),
              style: TextStyle(
                  color: fg, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'of ${formatMoneyRounded(target)} · $reached of $count reached',
            style: TextStyle(color: fg.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: ratio.toDouble(),
            color: fg,
            backgroundColor: fg.withValues(alpha: 0.25),
          ),
        ],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final SavingsGoal goal;
  final DateTime now;
  final VoidCallback onAdd;
  final VoidCallback? onWithdraw;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _GoalCard({
    required this.goal,
    required this.now,
    required this.onAdd,
    required this.onWithdraw,
    required this.onEdit,
    required this.onDelete,
  });

  /// The status line under the amounts: what the deadline asks for per month,
  /// or that it has slipped, or that the goal is done.
  (String, Color)? _status(BuildContext context) {
    if (goal.isComplete) return ('Goal reached', incomeColor(context));
    if (goal.isOverdue(now)) {
      return (
        'Target date passed · ${formatMoney(goal.remaining)} to go',
        dangerColor(context)
      );
    }
    final monthly = goal.monthlyNeeded(now);
    final months = goal.monthsLeft(now);
    if (monthly == null || months == null) return null;
    return (
      '${formatMoneyRounded(monthly)}/month for $months '
          'month${months == 1 ? '' : 's'} · by ${formatShortDate(goal.targetDate!)}',
      mutedTextColor(context)
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = goal.color == null ? scheme.primary : Color(goal.color!);
    final status = _status(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 4, 8),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: goal.progress,
                          strokeWidth: 6,
                          color: color,
                          backgroundColor: color.withValues(alpha: 0.15),
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      goal.isComplete
                          ? Icon(Icons.check, color: color)
                          : Text('${(goal.progress * 100).floor()}%',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(goal.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('${formatMoney(goal.saved)} of '
                          '${formatMoneyRounded(goal.target)}'),
                      if (status != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(status.$1,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: status.$2,
                                  fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Goal options',
                  onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            // OverflowBar rather than Row: on a narrow phone (or with large
            // text) the two buttons stack instead of overflowing the card.
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 4,
                overflowAlignment: OverflowBarAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: onWithdraw,
                    icon: const Icon(Icons.remove, size: 18),
                    label: const Text('Withdraw'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add money'),
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
