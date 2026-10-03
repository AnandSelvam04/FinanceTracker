import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/budget_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/recurring_provider.dart';
import '../providers/template_provider.dart';
import '../services/db_service.dart';
import '../utils/app_colors.dart';
import '../utils/db_constants.dart';
import '../utils/insets.dart';
import '../widgets/category_avatar.dart';
import '../widgets/category_choice_chip.dart' show isSameCategory;
import '../widgets/empty_state.dart';

/// Lists the categories in use, with a way to rename one or merge it into
/// another.
///
/// Categories are free text, so a typo ("Grocery" next to "Groceries") used to
/// split spending, budgets and charts for good — every past row kept the stray
/// spelling. Renaming here rewrites the transactions, budgets, recurring rules
/// and quick-add templates that use it in one step.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  String _type = DbConstants.txExpense;
  List<({String category, int count})>? _usage;

  bool get _isIncome => _type == DbConstants.txIncome;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final usage = await DBService().categoryUsage(_type);
    if (mounted) setState(() => _usage = usage);
  }

  Future<void> _rename(String from) async {
    final others = [
      for (final u in _usage ?? const <({String category, int count})>[])
        if (u.category != from) u.category,
    ];
    final to = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(from: from, others: others),
    );
    if (to == null || !mounted) return;
    final expenses = context.read<ExpenseProvider>();
    final budgets = context.read<BudgetProvider>();
    final recurring = context.read<RecurringProvider>();
    final templates = context.read<TemplateProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final merging = others.any((c) => isSameCategory(c, to));
    final moved = await DBService().renameCategory(from, to, type: _type);
    await Future.wait([
      expenses.reloadLoadedYears(),
      budgets.fetchBudgets(),
      recurring.fetchRules(),
      templates.fetchTemplates(),
    ]);
    await _load();
    messenger.showSnackBar(SnackBar(
      content: Text(merging
          ? 'Merged "$from" into "$to" ($moved moved)'
          : 'Renamed "$from" to "$to" ($moved updated)'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final usage = _usage;
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: DbConstants.txExpense, label: Text('Expense')),
                  ButtonSegment(
                      value: DbConstants.txIncome, label: Text('Income')),
                ],
                selected: {_type},
                onSelectionChanged: (s) {
                  setState(() {
                    _type = s.first;
                    _usage = null;
                  });
                  _load();
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Tap a category to rename it, or give it the name of another '
              'one to merge the two.',
              style: TextStyle(color: mutedTextColor(context), fontSize: 13),
            ),
          ),
          Expanded(
            child: usage == null
                ? const Center(child: CircularProgressIndicator())
                : usage.isEmpty
                    ? EmptyState(
                        icon: Icons.category_outlined,
                        title: _isIncome
                            ? 'No income sources yet'
                            : 'No categories yet',
                        message: 'Categories appear here once a transaction '
                            'uses them.',
                      )
                    : ListView.separated(
                        padding: scrollPadding(context, all: 12),
                        itemCount: usage.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, i) {
                          final u = usage[i];
                          return Card(
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              leading: CategoryAvatar(category: u.category),
                              title: Text(u.category,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(u.count == 1
                                  ? '1 transaction'
                                  : '${u.count} transactions'),
                              trailing: const Icon(Icons.edit_outlined),
                              onTap: () => _rename(u.category),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// Asks for a new name, offering the other categories as one-tap merge
/// targets and saying plainly when the name typed will merge.
class _RenameDialog extends StatefulWidget {
  final String from;
  final List<String> others;
  const _RenameDialog({required this.from, required this.others});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.from);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The existing category the typed name lands on, if any — spelled as it is
  /// stored, so a merge keeps the established spelling.
  String? get _mergeTarget {
    final typed = _controller.text.trim();
    for (final c in widget.others) {
      if (isSameCategory(c, typed)) return c;
    }
    return null;
  }

  String get _result => _mergeTarget ?? _controller.text.trim();

  bool get _canSave {
    final typed = _controller.text.trim();
    return typed.isNotEmpty && typed != widget.from;
  }

  @override
  Widget build(BuildContext context) {
    final target = _mergeTarget;
    return AlertDialog(
      title: Text('Rename "${widget.from}"'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'New name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text(
              target != null
                  ? 'Merges into "$target". Transactions, budgets, recurring '
                      'rules and quick adds all move over; this cannot be undone.'
                  : 'Updates every transaction, budget, recurring rule and '
                      'quick add that uses it.',
              style: TextStyle(fontSize: 12, color: mutedTextColor(context)),
            ),
            if (widget.others.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Or merge into',
                  style:
                      TextStyle(fontSize: 12, color: mutedTextColor(context))),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final c in widget.others)
                    ChoiceChip(
                      label: Text(c),
                      selected: c == target,
                      onSelected: (_) => setState(() => _controller.text = c),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSave ? () => Navigator.pop(context, _result) : null,
          child: Text(target != null ? 'Merge' : 'Rename'),
        ),
      ],
    );
  }
}
