import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/budget_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/recurring_provider.dart';
import '../providers/template_provider.dart';
import '../services/db_service.dart';
import '../utils/app_colors.dart';
import '../utils/category_colors.dart';
import '../utils/category_icons.dart';
import '../utils/category_store.dart';
import '../utils/db_constants.dart';
import '../utils/insets.dart';
import '../widgets/category_avatar.dart';
import '../widgets/category_choice_chip.dart' show isSameCategory;
import '../widgets/empty_state.dart';
import '../utils/font_sizes.dart';
import '../utils/dimens.dart';

/// Lists the categories — the ones transactions use, the user's own and the
/// built-in ones — with a way to add one, give it an icon and colour, rename
/// or merge it, and remove it.
///
/// Categories are text on a transaction, so a typo ("Grocery" next to
/// "Groceries") used to split spending, budgets and charts for good — every
/// past row kept the stray spelling. Renaming here rewrites the transactions,
/// budgets, recurring rules and quick-add templates that use it in one step.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

typedef _Row = ({String category, int count});

class _CategoriesScreenState extends State<CategoriesScreen> {
  String _type = DbConstants.txExpense;
  List<_Row>? _usage;

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

  /// The categories in use, then the ones on offer that nothing uses yet.
  List<_Row> get _rows {
    final usage = _usage ?? const <_Row>[];
    return [
      ...usage,
      for (final c in CategoryStore.instance.offered(_type))
        if (!usage.any((u) => isSameCategory(u.category, c)))
          (category: c, count: 0),
    ];
  }

  /// Rewrites [from] as [to] everywhere and reloads what shows categories.
  /// Returns how many transactions moved.
  Future<int> _move(String from, String to, {required bool merging}) async {
    final expenses = context.read<ExpenseProvider>();
    final budgets = context.read<BudgetProvider>();
    final recurring = context.read<RecurringProvider>();
    final templates = context.read<TemplateProvider>();
    final moved = await expenses.renameCategory(from, to, type: _type);
    await CategoryStore.instance.rename(_type, from, to, merged: merging);
    await Future.wait([
      budgets.fetchBudgets(),
      recurring.fetchRules(),
      templates.fetchTemplates(),
    ]);
    return moved;
  }

  Future<void> _add() async {
    final result = await showDialog<_CategoryEdit>(
      context: context,
      builder: (_) => _CategoryDialog(
        income: _isIncome,
        others: [for (final r in _rows) r.category],
      ),
    );
    if (result == null || !mounted) return;
    await CategoryStore.instance
        .put(_type, result.name, icon: result.icon, color: result.color);
    if (mounted) setState(() {});
  }

  Future<void> _edit(_Row row) async {
    final from = row.category;
    final others = [
      for (final r in _rows)
        if (r.category != from) r.category,
    ];
    final existing = CategoryStore.instance.entry(_type, from);
    final result = await showDialog<_CategoryEdit>(
      context: context,
      builder: (_) => _CategoryDialog(
        income: _isIncome,
        from: from,
        others: others,
        icon: existing?.icon,
        color: existing?.color,
      ),
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final expenses = context.read<ExpenseProvider>();
    final to = result.name;
    final merging = others.any((c) => isSameCategory(c, to));
    if (to != from) {
      final moved = await _move(from, to, merging: merging);
      messenger.showSnackBar(SnackBar(
        content: Text(merging
            ? 'Merged "$from" into "$to" ($moved moved)'
            : 'Renamed "$from" to "$to" ($moved updated)'),
      ));
    }
    // A merge keeps the look of the category merged into.
    if (!merging) {
      final changed =
          result.icon != existing?.icon || result.color != existing?.color;
      if (changed) {
        await CategoryStore.instance
            .put(_type, to, icon: result.icon, color: result.color);
        // Charts colour their bars by category; have them redraw.
        expenses.categoryLooksChanged();
      }
    }
    await _load();
  }

  Future<void> _delete(_Row row) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = row.category;
    if (row.count == 0) {
      await CategoryStore.instance.remove(_type, name);
      if (mounted) setState(() {});
      messenger.showSnackBar(SnackBar(content: Text('Removed "$name"')));
      return;
    }
    // A category with transactions can't just vanish: they need a new home.
    final others = [
      for (final r in _rows)
        if (r.category != name) r.category,
    ];
    final target = await showDialog<String>(
      context: context,
      builder: (_) => _MoveDialog(from: name, count: row.count, others: others),
    );
    if (target == null || !mounted) return;
    final moved = await _move(name, target, merging: true);
    await _load();
    messenger.showSnackBar(
        SnackBar(content: Text('Removed "$name" ($moved moved to "$target")')));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _usage == null ? null : _rows;
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(_isIncome ? 'New source' : 'New category'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.lg, Space.md, Space.lg, Space.xs),
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
            padding: const EdgeInsets.fromLTRB(
                Space.lg, Space.sm, Space.lg, Space.xs),
            child: Text(
              'Tap a category to rename it or change its icon and colour. '
              'Give it the name of another one to merge the two.',
              style: TextStyle(
                  color: mutedTextColor(context), fontSize: FontSizes.body),
            ),
          ),
          Expanded(
            child: rows == null
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? EmptyState(
                        icon: Icons.category_outlined,
                        title: _isIncome
                            ? 'No income sources yet'
                            : 'No categories yet',
                        message: 'Add one to pick it on your next '
                            'transaction.',
                        actionLabel: _isIncome ? 'New source' : 'New category',
                        onAction: _add,
                      )
                    : ListView.separated(
                        padding: scrollPadding(context, all: Space.md, fab: true),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: Space.xs),
                        itemBuilder: (context, i) {
                          final r = rows[i];
                          return Card(
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              leading: CategoryAvatar(category: r.category),
                              title: Text(r.category,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(switch (r.count) {
                                0 => 'Not used yet',
                                1 => '1 transaction',
                                _ => '${r.count} transactions',
                              }),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Remove ${r.category}',
                                onPressed: () => _delete(r),
                              ),
                              onTap: () => _edit(r),
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

/// What the add/edit dialog returns.
typedef _CategoryEdit = ({String name, String? icon, int? color});

/// Adds a category, or edits one: its name (offering the other categories as
/// one-tap merge targets and saying plainly when the name typed will merge),
/// its icon and its colour.
class _CategoryDialog extends StatefulWidget {
  /// The category being edited; null when adding one.
  final String? from;
  final bool income;
  final List<String> others;
  final String? icon;
  final int? color;
  const _CategoryDialog({
    this.from,
    required this.income,
    required this.others,
    this.icon,
    this.color,
  });

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final _controller = TextEditingController(text: widget.from ?? '');
  late String? _icon = widget.icon;
  late int? _color = widget.color;

  bool get _adding => widget.from == null;

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
    if (typed.isEmpty) return false;
    // A new category can't take a name already in the list.
    if (_adding) return _mergeTarget == null;
    return typed != widget.from ||
        _icon != widget.icon ||
        _color != widget.color;
  }

  @override
  Widget build(BuildContext context) {
    final target = _mergeTarget;
    final scheme = Theme.of(context).colorScheme;
    final muted =
        TextStyle(fontSize: FontSizes.caption, color: mutedTextColor(context));
    // What the avatar will look like with the choices made so far.
    final name = _controller.text.trim().isEmpty
        ? (widget.from ?? '')
        : _controller.text.trim();
    final color =
        _color != null ? Color(_color!) : CategoryColors.forCategory(name);
    final icon = categoryIconChoices[_icon] ?? categoryIcon(name);
    return AlertDialog(
      title: Text(_adding
          ? (widget.income ? 'New income source' : 'New category')
          : 'Edit "${widget.from}"'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          // Room for the name field's floating label, which the scroll view
          // would otherwise clip at its top edge.
          padding: const EdgeInsets.only(top: Space.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.18),
                    child: Icon(icon,
                        color: CategoryColors.foreground(
                            color, Theme.of(context).brightness)),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: _adding,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Name'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              if (_adding && target != null)
                Text('"$target" already exists.',
                    style: TextStyle(
                        fontSize: FontSizes.caption, color: scheme.error))
              else if (!_adding)
                Text(
                  target != null
                      ? 'Merges into "$target". Transactions, budgets, '
                          'recurring rules and quick adds all move over; this '
                          'cannot be undone.'
                      : 'A new name updates every transaction, budget, '
                          'recurring rule and quick add that uses it.',
                  style: muted,
                ),
              if (!_adding && widget.others.isNotEmpty) ...[
                const SizedBox(height: Space.md),
                Text('Or merge into', style: muted),
                const SizedBox(height: Space.sm),
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
              // A merge takes on the other category's look.
              if (_adding || target == null) ...[
                const SizedBox(height: Space.lg),
                Text('Colour', style: muted),
                const SizedBox(height: Space.sm),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in CategoryColors.palette)
                      _Swatch(
                        color: c,
                        selected: _color == c.toARGB32(),
                        onTap: () => setState(() => _color =
                            _color == c.toARGB32() ? null : c.toARGB32()),
                      ),
                  ],
                ),
                const SizedBox(height: Space.lg),
                Text('Icon', style: muted),
                const SizedBox(height: Space.sm),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final e in categoryIconChoices.entries)
                      IconButton(
                        isSelected: _icon == e.key,
                        style: IconButton.styleFrom(
                          backgroundColor:
                              _icon == e.key ? scheme.primaryContainer : null,
                          foregroundColor: _icon == e.key
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                        icon: Icon(e.value),
                        tooltip: e.key,
                        // Tapping the chosen one again goes back to automatic.
                        onPressed: () => setState(
                            () => _icon = _icon == e.key ? null : e.key),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSave
              ? () => Navigator.pop<_CategoryEdit>(
                  context, (name: _result, icon: _icon, color: _color))
              : null,
          child: Text(_adding
              ? 'Add'
              : target != null
                  ? 'Merge'
                  : 'Save'),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch(
      {required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Colour',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(
                    color: Theme.of(context).colorScheme.onSurface, width: 3)
                : null,
          ),
          child: selected
              ? const Icon(Icons.check, size: 18, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

/// Asks where a removed category's transactions should go.
class _MoveDialog extends StatefulWidget {
  final String from;
  final int count;
  final List<String> others;
  const _MoveDialog(
      {required this.from, required this.count, required this.others});

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  String? _target;

  @override
  Widget build(BuildContext context) {
    final n = widget.count;
    return AlertDialog(
      title: Text('Remove "${widget.from}"?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.others.isEmpty
                ? 'It has $n transaction${n == 1 ? '' : 's'} and there is no '
                    'other category to move them to. Add one first.'
                : 'Its $n transaction${n == 1 ? '' : 's'}, with any budgets, '
                    'recurring rules and quick adds, move to the category '
                    'you pick. This cannot be undone.'),
            const SizedBox(height: Space.md),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final c in widget.others)
                  ChoiceChip(
                    label: Text(c),
                    selected: c == _target,
                    onSelected: (_) => setState(() => _target = c),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _target == null ? null : () => Navigator.pop(context, _target),
          child: const Text('Move and remove'),
        ),
      ],
    );
  }
}
