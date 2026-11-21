import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/recurring_rule.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../services/recurring_detector.dart';
import '../providers/recurring_provider.dart';
import '../utils/haptics.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';
import '../utils/insets.dart';
import '../utils/date_format.dart';
import '../widgets/category_avatar.dart';
import '../widgets/empty_state.dart';
import '../widgets/swipe_actions.dart';
import '../utils/dimens.dart';
import '../utils/font_sizes.dart';
import '../widgets/form_page.dart';

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  final _formKey = GlobalKey<FormState>();
  String _description = '';
  int _amount = 0; // minor units
  String _category = '';
  String _type = DbConstants.txExpense;
  String _frequency = DbConstants.freqMonthly;
  int? _accountId;
  DateTime _nextDue = DateTime.now();
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(context.read<RecurringProvider>().fetchRules());
      unawaited(context.read<AccountProvider>().fetchAccounts());
      // The six months the suggestions look back over can reach last year.
      final now = DateTime.now();
      unawaited(context
          .read<ExpenseProvider>()
          .ensureYearsLoaded({now.year, now.year - 1}));
    });
    unawaited(_loadDismissed());
  }

  static const _kDismissed = 'dismissedRecurringSuggestions';

  /// Payees whose suggestion was waved away, so they aren't offered again.
  List<String> _dismissed = const [];

  Future<void> _loadDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kDismissed) ?? const [];
    if (mounted) setState(() => _dismissed = list);
  }

  Future<void> _dismiss(RecurringSuggestion s) async {
    final next = [..._dismissed, s.description.toLowerCase()];
    setState(() => _dismissed = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kDismissed, next);
  }

  static String _freqLabel(String freq) {
    switch (freq) {
      case DbConstants.freqDaily:
        return 'Daily';
      case DbConstants.freqWeekly:
        return 'Weekly';
      case DbConstants.freqMonthly:
        return 'Monthly';
      case DbConstants.freqYearly:
        return 'Yearly';
      default:
        return freq;
    }
  }

  /// Edits [rule], or adds a new one — filled in from [prefill] when given
  /// (a suggested subscription).
  Future<void> _showRuleDialog(
      {RecurringRule? rule, RecurringRule? prefill}) async {
    final from = rule ?? prefill;
    _description = from?.description ?? '';
    _amount = from?.amount ?? 0;
    _category = from?.category ?? '';
    _type = from?.type ?? DbConstants.txExpense;
    _frequency = from?.frequency ?? DbConstants.freqMonthly;
    _accountId = from?.accountId;
    _nextDue = from?.nextDue ?? DateTime.now();
    _endDate = from?.endDate;

    final accounts =
        context.read<AccountProvider>().pickable([from?.accountId]);
    // A SIP files contributions into an investment type: it has no
    // expense/income type to pick, and its category is that investment type.
    final isSip = rule?.isInvestment ?? false;

    // A full page: the rule's fields didn't fit a dialog above the keyboard.
    await showFormPage(
      context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => FormPage(
          title: Text(rule == null
              ? 'Add recurring'
              : isSip
                  ? 'Edit SIP'
                  : 'Edit recurring'),
          content: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: _description,
                    decoration: const InputDecoration(labelText: 'Description'),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                    onSaved: (v) => _description = v ?? '',
                  ),
                  TextFormField(
                    initialValue:
                        _amount == 0 ? '' : minorToEditString(_amount),
                    decoration: const InputDecoration(labelText: 'Amount'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: validateAmountField,
                    onSaved: (v) => _amount = parseMinor(v ?? '0') ?? 0,
                  ),
                  TextFormField(
                    initialValue: _category,
                    decoration: InputDecoration(
                        labelText: isSip ? 'Investment type' : 'Category'),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                    onSaved: (v) => _category = v ?? '',
                  ),
                  if (!isSip)
                    DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: [
                        DropdownMenuItem(
                            value: DbConstants.txExpense,
                            child: const Text('Expense')),
                        DropdownMenuItem(
                            value: DbConstants.txIncome,
                            child: const Text('Income')),
                      ],
                      onChanged: (v) => _type = v ?? _type,
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: _frequency,
                    decoration: const InputDecoration(labelText: 'Frequency'),
                    items: RecurringRule.frequencies
                        .map((f) => DropdownMenuItem(
                            value: f, child: Text(_freqLabel(f))))
                        .toList(),
                    onChanged: (v) => _frequency = v ?? _frequency,
                  ),
                  if (accounts.isNotEmpty)
                    DropdownButtonFormField<int?>(
                      isExpanded: true,
                      initialValue: _accountId,
                      decoration: InputDecoration(
                          labelText: isSip ? 'Paid from' : 'Account'),
                      items: [
                        DropdownMenuItem<int?>(
                            value: null, child: const Text('None')),
                        ...accounts.map((a) => DropdownMenuItem<int?>(
                            value: a.id,
                            child:
                                Text(a.name, overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (v) => _accountId = v,
                    ),
                  const SizedBox(height: Space.sm),
                  Row(
                    children: [
                      Expanded(
                          child:
                              Text('Next due: ${formatDateWithDay(_nextDue)}')),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _nextDue,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() {
                              _nextDue = picked;
                              // An end date before the first occurrence would
                              // end the rule before it ever posts.
                              if (_endDate != null &&
                                  _endDate!
                                      .isBefore(DateUtils.dateOnly(picked))) {
                                _endDate = null;
                              }
                            });
                          }
                        },
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(_endDate == null
                            ? 'Ends: never'
                            : 'Ends: ${formatDateWithDay(_endDate!)}'),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            // Never before firstDate, which the picker asserts.
                            initialDate: _endDate != null &&
                                    !_endDate!
                                        .isBefore(DateUtils.dateOnly(_nextDue))
                                ? _endDate!
                                : _nextDue,
                            firstDate: _nextDue,
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() => _endDate = picked);
                          }
                        },
                        child: const Text('Set end'),
                      ),
                      if (_endDate != null)
                        TextButton(
                          onPressed: () =>
                              setDialogState(() => _endDate = null),
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (rule != null)
              TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                onPressed: () {
                  Navigator.of(context).pop();
                  unawaited(_confirmDeleteRule(rule));
                },
                child: const Text('Delete'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (_formKey.currentState!.validate()) {
                  _formKey.currentState!.save();
                  final newRule = RecurringRule(
                    id: rule?.id,
                    description: _description,
                    amount: _amount,
                    category: _category,
                    type: _type,
                    accountId: _accountId,
                    frequency: _frequency,
                    nextDue: _nextDue,
                    // Keep the rule's anchor unless the due date was changed.
                    // Re-deriving it from nextDue moved a monthly rule anchored
                    // on the 31st to the 28th if it was edited while its next
                    // occurrence sat clamped to a short month.
                    anchorDay: rule != null && _nextDue == rule.nextDue
                        ? rule.anchorDay
                        : null,
                    enabled: rule?.enabled ?? true,
                    endDate: _endDate,
                    // Preserve the SIP flag; this dialog only edits the common
                    // fields, so an investment rule must stay an investment.
                    isInvestment: rule?.isInvestment ?? false,
                  );
                  final provider = context.read<RecurringProvider>();
                  if (rule == null) {
                    await provider.addRule(newRule);
                  } else {
                    await provider.updateRule(newRule);
                  }
                  if (context.mounted) Navigator.of(context).pop();
                }
              },
              child: Text(rule == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteRule(RecurringRule rule) async {
    final provider = context.read<RecurringProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete recurring rule?'),
        content: Text('Stop and remove "${rule.description}"? Transactions it '
            'has already posted are kept.'),
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
    if (ok == true) await provider.deleteRule(rule.id!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      body: Consumer<RecurringProvider>(
        builder: (context, provider, _) {
          // Soonest first, so what posts next is at the top; paused rules
          // after the running ones.
          final rules = [...provider.rules]..sort((a, b) {
              if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
              return a.nextDue.compareTo(b.nextDue);
            });
          final suggestions = RecurringDetector.suggestions(
            context.watch<ExpenseProvider>().expenses,
            known: [
              for (final r in provider.rules) r.description,
              ..._dismissed,
            ],
          ).take(3).toList();
          final head = <Widget>[
            if (rules.isNotEmpty) _CommitmentsCard(rules: rules),
            if (suggestions.isNotEmpty)
              _SuggestionsCard(
                suggestions: suggestions,
                onAdd: (s) => _showRuleDialog(
                    prefill: RecurringRule(
                  description: s.description,
                  amount: s.amount,
                  category: s.category,
                  accountId: s.accountId,
                  frequency: DbConstants.freqMonthly,
                  nextDue: s.nextDue(DateTime.now()),
                )),
                onDismiss: _dismiss,
              ),
          ];
          if (rules.isEmpty && head.isEmpty) {
            return EmptyState(
              icon: Icons.repeat,
              title: 'No recurring transactions',
              message:
                  'Add rent, salary, or bills and they post automatically.',
              actionLabel: 'Add recurring',
              onAction: () => _showRuleDialog(),
            );
          }
          return ListView.separated(
            itemCount: head.length + rules.length,
            padding: scrollPadding(context, all: Space.md, fab: true),
            separatorBuilder: (_, __) => const SizedBox(height: Space.sm),
            itemBuilder: (context, index) {
              if (index < head.length) return head[index];
              final rule = rules[index - head.length];
              return SwipeActions(
                key: ValueKey('rule-${rule.id}'),
                onEdit: () => _showRuleDialog(rule: rule),
                onDelete: () => _confirmDeleteRule(rule),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    // Expense rules wear their category's avatar, so "Netflix"
                    // looks the same here as on the dashboard and transaction
                    // list; income and SIP rules keep the green up-arrow.
                    leading:
                        !rule.isInvestment && rule.type != DbConstants.txIncome
                            ? CategoryAvatar(category: rule.category)
                            : CircleAvatar(
                                backgroundColor: incomeAvatarColor(context),
                                child: Icon(
                                    rule.isInvestment
                                        ? Icons.trending_up
                                        : Icons.south_west,
                                    color: incomeColor(context)),
                              ),
                    // The amount sits beside the name and Delete lives in the
                    // edit dialog: with both in the trailing slot the name and
                    // category broke mid-word on a phone.
                    title: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(rule.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: Space.sm),
                        // In the account's currency: a rule posting to a
                        // USD account showed its amount with the base symbol.
                        Text(
                            switch (context
                                .watch<AccountProvider>()
                                .accountById(rule.accountId)) {
                              final a? when a.isForeign =>
                                formatMoneyIn(a.symbol, rule.amount),
                              _ => formatMoneyRounded(rule.amount),
                            },
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    subtitle: Text(
                        '${rule.isInvestment ? 'SIP · ' : ''}${rule.category} · ${_freqLabel(rule.frequency)} · next ${formatCompactDate(rule.nextDue)}'
                        '${rule.endDate != null ? ' · ends ${formatCompactDate(rule.endDate!)}' : ''}'),
                    trailing: Switch(
                      value: rule.enabled,
                      onChanged: (_) {
                        Haptics.light();
                        unawaited(provider.toggleEnabled(rule));
                      },
                    ),
                    onTap: () => _showRuleDialog(rule: rule),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add recurring rule',
        onPressed: () => _showRuleDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// What the running rules come to in a month, in the base currency: bills
/// and SIPs going out, income coming in.
class _CommitmentsCard extends StatelessWidget {
  final List<RecurringRule> rules;

  const _CommitmentsCard({required this.rules});

  /// How many times a month a rule of [frequency] posts, on average.
  static double _perMonth(String frequency) => switch (frequency) {
        DbConstants.freqDaily => 365 / 12,
        DbConstants.freqWeekly => 52 / 12,
        DbConstants.freqYearly => 1 / 12,
        _ => 1,
      };

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountProvider>();
    var out = 0.0;
    var into = 0.0;
    var count = 0;
    for (final r in rules) {
      if (!r.enabled) continue;
      count++;
      final rate = accounts.accountById(r.accountId)?.rate ?? 1.0;
      final monthly = toBaseMinor(r.amount, rate) * _perMonth(r.frequency);
      if (r.type == DbConstants.txIncome && !r.isInvestment) {
        into += monthly;
      } else {
        out += monthly;
      }
    }
    final muted = mutedTextColor(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Going out each month',
                      style:
                          TextStyle(fontSize: FontSizes.caption, color: muted)),
                  const SizedBox(height: Space.xxs),
                  Text(formatMoneyRounded(out.round()),
                      style: TextStyle(
                          fontSize: FontSizes.title,
                          fontWeight: FontWeight.bold,
                          color: expenseColor(context))),
                  Text('$count running rule${count == 1 ? '' : 's'}',
                      style:
                          TextStyle(fontSize: FontSizes.caption, color: muted)),
                ],
              ),
            ),
            if (into > 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Coming in',
                      style:
                          TextStyle(fontSize: FontSizes.caption, color: muted)),
                  const SizedBox(height: Space.xxs),
                  Text(formatMoneyRounded(into.round()),
                      style: TextStyle(
                          fontSize: FontSizes.title,
                          fontWeight: FontWeight.bold,
                          color: incomeColor(context))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Spends that recur in the history but have no rule yet, each with Add
/// (opens the form filled in) and a dismiss.
class _SuggestionsCard extends StatelessWidget {
  final List<RecurringSuggestion> suggestions;
  final void Function(RecurringSuggestion) onAdd;
  final void Function(RecurringSuggestion) onDismiss;

  const _SuggestionsCard({
    required this.suggestions,
    required this.onAdd,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountProvider>();
    final muted = mutedTextColor(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.lg, Space.xs, Space.lg, Space.xs),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_outlined,
                      size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: Space.sm),
                  const Expanded(
                    child: Text('These look like regular bills',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            for (final s in suggestions)
              ListTile(
                leading: CategoryAvatar(category: s.category),
                title: Text(s.description,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${switch (accounts.accountById(s.accountId)) {
                      final a? when a.isForeign =>
                        formatMoneyIn(a.symbol, s.amount),
                      _ => formatMoneyRounded(s.amount),
                    }} · in ${s.months} of the last 6 months',
                    style: TextStyle(color: muted)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Not a regular bill',
                      onPressed: () => onDismiss(s),
                    ),
                    TextButton(
                      onPressed: () => onAdd(s),
                      child: const Text('Add'),
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
