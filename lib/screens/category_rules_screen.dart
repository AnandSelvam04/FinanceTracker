import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/category_rule.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../services/category_rules.dart';
import '../services/db_service.dart';
import '../utils/app_colors.dart';
import '../utils/category_store.dart';
import '../utils/date_format.dart';
import '../utils/db_constants.dart';
import '../utils/dimens.dart';
import '../utils/font_sizes.dart';
import '../utils/insets.dart';
import '../widgets/category_avatar.dart';
import '../widgets/category_picker.dart';
import '../widgets/empty_state.dart';
import '../widgets/swipe_actions.dart';

/// More → Auto-categorise: the user's rules ("if the description contains
/// *zomato*, file it under Food and tag it #eatingout"), in the order they are
/// tried. They file SMS and CSV imports and new expenses as the description is
/// typed, and can be run over past transactions.
class CategoryRulesScreen extends StatefulWidget {
  const CategoryRulesScreen({super.key});

  @override
  State<CategoryRulesScreen> createState() => _CategoryRulesScreenState();
}

class _CategoryRulesScreenState extends State<CategoryRulesScreen> {
  final _store = CategoryRuleStore.instance;

  /// Every transaction, for each rule's match count. Null while loading.
  List<Expense>? _rows;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final rows = await DBService().getExpenses();
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _edit({CategoryRule? rule}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CategoryRuleEditor(rule: rule)),
    );
    await _load();
  }

  Future<void> _delete(CategoryRule rule) async {
    final messenger = ScaffoldMessenger.of(context);
    final index = await _store.remove(rule.id);
    messenger.showSnackBar(SnackBar(
      content: Text('Deleted the rule ${rule.condition}'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => _store.add(rule, index: index),
      ),
    ));
  }

  Future<void> _applyAll() async {
    await applyRulesToPast(context);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final rules = _store.rules;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Auto-categorise'),
            actions: [
              if (rules.isNotEmpty)
                PopupMenuButton<String>(
                  onSelected: (_) => _applyAll(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'apply',
                      child: Text('Apply all rules to past transactions'),
                    ),
                  ],
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('New rule'),
          ),
          body: rules.isEmpty
              ? EmptyState(
                  icon: Icons.auto_fix_high,
                  title: 'No rules yet',
                  message: 'Tell the app how to file a merchant once — '
                      '"if it contains zomato, it\'s Food, tag #eatingout" — '
                      'and SMS imports, CSV imports and new expenses are '
                      'filed that way from then on. A rule can also tidy up '
                      'the transactions you already have.',
                  actionLabel: 'Create a rule',
                  onAction: () => _edit(),
                )
              : ReorderableListView.builder(
                  padding: scrollPadding(context, all: Space.md, fab: true),
                  header: Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: Text(
                      'Rules are tried from the top; the first that matches '
                      'files the transaction. Hold and drag to reorder.',
                      style: TextStyle(
                          fontSize: FontSizes.caption,
                          color: mutedTextColor(context)),
                    ),
                  ),
                  itemCount: rules.length,
                  onReorderItem: _store.reorder,
                  itemBuilder: (context, i) {
                    final r = rules[i];
                    final rows = _rows;
                    final count = rows == null
                        ? null
                        : CategoryRules.matching(r, rows).length;
                    return SwipeActions(
                      key: ValueKey('rule-${r.id}'),
                      onEdit: () => _edit(rule: r),
                      onDelete: () => _delete(r),
                      child: Card(
                        margin: const EdgeInsets.only(bottom: Space.sm),
                        child: ListTile(
                          leading: Opacity(
                            opacity: r.enabled ? 1 : 0.4,
                            child: CategoryAvatar(category: r.category),
                          ),
                          title: Text(r.condition,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text([
                            '${r.isIncome ? 'Income' : 'Expense'} → ${r.category}',
                            if (r.tag != null) '#${r.tag}',
                            if (!r.enabled)
                              'Off'
                            else if (count != null)
                              '$count past match${count == 1 ? '' : 'es'}',
                          ].join(' · ')),
                          trailing: Switch(
                            value: r.enabled,
                            onChanged: (on) =>
                                _store.update(r.copyWith(enabled: on)),
                          ),
                          onTap: () => _edit(rule: r),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

/// Runs the rules over every past transaction — or just [only] — after
/// showing how many would change and asking. Offers Undo afterwards.
/// Returns how many rows changed.
Future<int> applyRulesToPast(BuildContext context, {CategoryRule? only}) async {
  final messenger = ScaffoldMessenger.of(context);
  final provider = context.read<ExpenseProvider>();
  final rows = await DBService().getExpenses();
  final changes =
      CategoryRules.changes(CategoryRuleStore.instance.rules, rows, only: only);
  if (!context.mounted) return 0;
  if (changes.isEmpty) {
    if (only == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Nothing to change: your transactions already '
              'match your rules.')));
    }
    return 0;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => _ApplyDialog(changes: changes),
  );
  if (ok != true || !context.mounted) return 0;
  final n = await provider.setCategoriesAndNotes({
    for (final c in changes) c.row.id!: (category: c.category, note: c.note),
  });
  messenger.showSnackBar(SnackBar(
    content: Text('Updated $n transaction${n == 1 ? '' : 's'}'),
    action: SnackBarAction(
      label: 'Undo',
      onPressed: () => provider.setCategoriesAndNotes({
        for (final c in changes)
          c.row.id!: (category: c.row.category, note: c.row.note),
      }),
    ),
  ));
  return n;
}

/// "Update 23 transactions?" with a few of them shown, old category → new.
class _ApplyDialog extends StatelessWidget {
  final List<RuleChange> changes;
  const _ApplyDialog({required this.changes});

  @override
  Widget build(BuildContext context) {
    final n = changes.length;
    final sample = changes.take(5).toList();
    final tags = changes.any((c) => c.rule.tag != null);
    return AlertDialog(
      title: Text('Update $n past transaction${n == 1 ? '' : 's'}?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tags
                ? 'Each gets the category its rule sets, and the rule\'s tag '
                    'is added to its note.'
                : 'Each gets the category its rule sets.'),
            const SizedBox(height: Space.md),
            for (final c in sample)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: Text(
                  '${c.row.displayName}: ${c.row.category} → ${c.category}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: FontSizes.caption),
                ),
              ),
            if (n > sample.length)
              Text('…and ${n - sample.length} more',
                  style: TextStyle(
                      fontSize: FontSizes.caption,
                      color: mutedTextColor(context))),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Update')),
      ],
    );
  }
}

/// Creates or edits one rule, with a live preview of the past transactions
/// it matches. [rule] edits an existing rule; [draft] starts a new one filled
/// in (as offered after recategorising a transaction).
class CategoryRuleEditor extends StatefulWidget {
  final CategoryRule? rule;
  final CategoryRule? draft;
  const CategoryRuleEditor({super.key, this.rule, this.draft});

  @override
  State<CategoryRuleEditor> createState() => _CategoryRuleEditorState();
}

class _CategoryRuleEditorState extends State<CategoryRuleEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _pattern = TextEditingController(text: _start?.pattern ?? '');
  late final _tag = TextEditingController(text: _start?.tag ?? '');
  late RuleMatch _match = _start?.match ?? RuleMatch.contains;
  late String _type = _start?.type ?? DbConstants.txExpense;
  late String _category = _start?.category ?? '';
  String? _categoryError;
  List<Expense>? _rows;
  bool _saving = false;

  CategoryRule? get _start => widget.rule ?? widget.draft;
  bool get _editing => widget.rule != null;

  @override
  void initState() {
    super.initState();
    _pattern.addListener(_changed);
    _tag.addListener(_changed);
    unawaited(_load());
  }

  @override
  void dispose() {
    _pattern.dispose();
    _tag.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  Future<void> _load() async {
    final rows = await DBService().getExpenses();
    if (mounted) setState(() => _rows = rows);
  }

  /// The rule as the form now stands.
  CategoryRule get _current => CategoryRule(
        id: widget.rule?.id ?? CategoryRuleStore.newId(),
        match: _match,
        pattern: _pattern.text.trim(),
        type: _type,
        category: _category.trim(),
        tag: _tag.text,
        enabled: widget.rule?.enabled ?? true,
      );

  /// The store's rules with this one in its place (or at the end when new),
  /// so the preview counts what it would really change.
  List<CategoryRule> _withCurrent(CategoryRule current) {
    final rules = [...CategoryRuleStore.instance.rules];
    final i = rules.indexWhere((r) => r.id == current.id);
    if (i == -1) {
      rules.add(current);
    } else {
      rules[i] = current;
    }
    return rules;
  }

  /// Another rule that looks for the same text the same way.
  CategoryRule? get _duplicate {
    final c = _current;
    final needle = CategoryRule.normalise(c.pattern);
    for (final r in CategoryRuleStore.instance.rules) {
      if (r.id == c.id) continue;
      if (r.type == c.type &&
          r.match == c.match &&
          CategoryRule.normalise(r.pattern) == needle) {
        return r;
      }
    }
    return null;
  }

  Future<void> _save() async {
    final validCategory = _category.trim().isNotEmpty;
    setState(() => _categoryError = validCategory
        ? null
        : (_type == DbConstants.txIncome
            ? 'Choose a source'
            : 'Choose a category'));
    if (!_formKey.currentState!.validate() || !validCategory) return;
    setState(() => _saving = true);
    final rule = _current;
    final store = CategoryRuleStore.instance;
    if (_editing) {
      await store.update(rule);
    } else {
      await store.add(rule);
    }
    await CategoryStore.instance.ensure(rule.type, rule.category);
    if (!mounted) return;
    // A rule tidies what is already there only when asked.
    await applyRulesToPast(context, only: rule);
    if (!mounted) return;
    Navigator.pop(context, rule);
  }

  Future<void> _delete() async {
    final rule = widget.rule;
    if (rule == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final store = CategoryRuleStore.instance;
    final index = await store.remove(rule.id);
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text('Deleted the rule ${rule.condition}'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => store.add(rule, index: index),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final rows = _rows;
    final valid = current.pattern.isNotEmpty;
    final matches = rows == null || !valid
        ? const <Expense>[]
        : CategoryRules.matching(current, rows);
    final changes = rows == null || !valid || current.category.isEmpty
        ? const <RuleChange>[]
        : CategoryRules.changes(_withCurrent(current), rows, only: current);
    final duplicate = valid ? _duplicate : null;
    final income = _type == DbConstants.txIncome;
    final muted = mutedTextColor(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit rule' : 'New rule'),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'Delete rule',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Space.lg),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: DbConstants.txExpense,
                            label: Text('Expense'),
                            icon: Icon(Icons.remove_circle_outline),
                          ),
                          ButtonSegment(
                            value: DbConstants.txIncome,
                            label: Text('Income'),
                            icon: Icon(Icons.add_circle_outline),
                          ),
                        ],
                        selected: {_type},
                        onSelectionChanged: (s) => setState(() {
                          if (s.first != _type) _category = '';
                          _type = s.first;
                        }),
                      ),
                    ),
                    const SizedBox(height: Space.lg),
                    Text('When the description',
                        style: TextStyle(
                            fontSize: FontSizes.caption, color: muted)),
                    const SizedBox(height: Space.xs),
                    Wrap(
                      spacing: Space.sm,
                      children: [
                        for (final m in RuleMatch.values)
                          ChoiceChip(
                            label: Text(m.label.toLowerCase()),
                            selected: _match == m,
                            onSelected: (_) => setState(() => _match = m),
                          ),
                      ],
                    ),
                    const SizedBox(height: Space.sm),
                    TextFormField(
                      controller: _pattern,
                      autofocus: !_editing && widget.draft == null,
                      decoration: const InputDecoration(
                        labelText: 'Text to look for',
                        hintText: 'zomato',
                        helperText: 'Capitals and punctuation are ignored',
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Enter the text to look for'
                          : null,
                    ),
                    if (duplicate != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.xs),
                        child: Text(
                          'Another rule already looks for this and files it '
                          'under ${duplicate.category}. The higher of the two '
                          'wins.',
                          style: TextStyle(
                              fontSize: FontSizes.caption,
                              color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    const SizedBox(height: Space.lg),
                    CategoryPickerField(
                      type: _type,
                      value: _category,
                      suggestions: CategoryStore.instance.offered(_type),
                      errorText: _categoryError,
                      onChanged: (c) => setState(() {
                        _category = c;
                        _categoryError = null;
                      }),
                    ),
                    const SizedBox(height: Space.lg),
                    TextFormField(
                      controller: _tag,
                      decoration: const InputDecoration(
                        labelText: 'Tag (optional)',
                        prefixText: '#',
                        hintText: 'eatingout',
                        helperText: 'Added to the note, and totalled under '
                            'More → Tags',
                      ),
                    ),
                    const SizedBox(height: Space.xl),
                    Text('Past transactions',
                        style: TextStyle(
                            fontSize: FontSizes.caption, color: muted)),
                    const SizedBox(height: Space.xs),
                    if (rows == null)
                      const LinearProgressIndicator()
                    else if (!valid)
                      Text(
                          'Enter the text to look for to see what it '
                          'matches.',
                          style: TextStyle(color: muted))
                    else
                      _Preview(
                        matches: matches,
                        changeCount:
                            current.category.isEmpty ? null : changes.length,
                        income: income,
                      ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.lg, Space.sm, Space.lg, Space.md),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_editing ? 'Save rule' : 'Create rule'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the rule being edited matches among past transactions.
class _Preview extends StatelessWidget {
  final List<Expense> matches;

  /// How many of [matches] the rule would change; null until a category is
  /// chosen, when that cannot be known.
  final int? changeCount;
  final bool income;

  const _Preview({
    required this.matches,
    required this.changeCount,
    required this.income,
  });

  @override
  Widget build(BuildContext context) {
    final muted = mutedTextColor(context);
    if (matches.isEmpty) {
      return Text(
          'Matches none of your ${income ? 'income' : 'expenses'} yet. It '
          'will file new ones as they arrive.',
          style: TextStyle(color: muted));
    }
    final n = matches.length;
    final sorted = [...matches]..sort((a, b) => b.date.compareTo(a.date));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Matches $n transaction${n == 1 ? '' : 's'}'
          '${switch (changeCount) {
            null => '. Choose a category to see how many would change.',
            0 => ', all already filed this way.',
            final c => ' · $c would change. You\'ll be asked before any are.',
          }}',
        ),
        const SizedBox(height: Space.sm),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (final e in sorted.take(5))
                ListTile(
                  dense: true,
                  leading: CategoryAvatar(category: e.category, radius: 14),
                  title: Text(e.displayName,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${e.category} · ${formatShortDate(e.date)}'),
                ),
              if (n > 5)
                Padding(
                  padding: const EdgeInsets.all(Space.sm),
                  child: Text('…and ${n - 5} more',
                      style:
                          TextStyle(fontSize: FontSizes.caption, color: muted)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
