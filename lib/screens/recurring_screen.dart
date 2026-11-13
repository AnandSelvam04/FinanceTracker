import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/recurring_rule.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/investment_provider.dart';
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
  int? _toAccountId;
  int _interval = 1;
  bool _askFirst = false;
  DateTime _nextDue = DateTime.now();
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RecurringProvider>().fetchRules();
      context.read<AccountProvider>().fetchAccounts();
    });
  }

  /// The schedules offered in the dialog, as (frequency, every N periods).
  static const _schedules = [
    (DbConstants.freqDaily, 1),
    (DbConstants.freqWeekly, 1),
    (DbConstants.freqWeekly, 2),
    (DbConstants.freqMonthly, 1),
    (DbConstants.freqMonthly, 3),
    (DbConstants.freqMonthly, 6),
    (DbConstants.freqYearly, 1),
  ];

  Future<void> _showRuleDialog({RecurringRule? rule}) async {
    _description = rule?.description ?? '';
    _amount = rule?.amount ?? 0;
    _category = rule?.category ?? '';
    _type = rule?.type ?? DbConstants.txExpense;
    _frequency = rule?.frequency ?? DbConstants.freqMonthly;
    _accountId = rule?.accountId;
    _toAccountId = rule?.toAccountId;
    _interval = rule?.interval ?? 1;
    _askFirst = rule?.askFirst ?? false;
    _nextDue = rule?.nextDue ?? DateTime.now();
    _endDate = rule?.endDate;

    final accounts = context.read<AccountProvider>().accounts;
    // A SIP files contributions into an investment type: it has no
    // expense/income type to pick, and its category is that investment type.
    final isSip = rule?.isInvestment ?? false;
    // A schedule the list doesn't offer (from a backup) stays selectable.
    final schedules = [
      ..._schedules,
      if (!_schedules.contains((_frequency, _interval)))
        (_frequency, _interval),
    ];

    bool transfer() => !isSip && _type == DbConstants.txTransfer;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(rule == null
              ? 'Add Recurring'
              : isSip
                  ? 'Edit SIP'
                  : 'Edit Recurring'),
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
                        // Needs an account on each side.
                        if (accounts.length >= 2 ||
                            _type == DbConstants.txTransfer)
                          DropdownMenuItem(
                              value: DbConstants.txTransfer,
                              child: const Text('Transfer between accounts')),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => _type = v ?? _type),
                    ),
                  // A transfer has no category: it isn't spending.
                  if (!transfer())
                    TextFormField(
                      initialValue: _category,
                      decoration: InputDecoration(
                          labelText: isSip ? 'Investment type' : 'Category'),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Required' : null,
                      onSaved: (v) => _category = v ?? '',
                    ),
                  DropdownButtonFormField<(String, int)>(
                    initialValue: (_frequency, _interval),
                    decoration: const InputDecoration(labelText: 'Repeats'),
                    items: [
                      for (final s in schedules)
                        DropdownMenuItem(
                            value: s,
                            child: Text(
                                RecurringRule.describeFrequency(s.$1, s.$2))),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      _frequency = v.$1;
                      _interval = v.$2;
                    },
                  ),
                  if (accounts.isNotEmpty)
                    DropdownButtonFormField<int?>(
                      isExpanded: true,
                      initialValue: _accountId,
                      decoration: InputDecoration(
                          labelText: isSip
                              ? 'Paid from'
                              : transfer()
                                  ? 'From'
                                  : 'Account'),
                      items: [
                        if (!transfer())
                          DropdownMenuItem<int?>(
                              value: null, child: const Text('None')),
                        ...accounts.map((a) => DropdownMenuItem<int?>(
                            value: a.id,
                            child:
                                Text(a.name, overflow: TextOverflow.ellipsis))),
                      ],
                      validator: (v) =>
                          transfer() && v == null ? 'Required' : null,
                      onChanged: (v) => _accountId = v,
                    ),
                  if (transfer())
                    DropdownButtonFormField<int?>(
                      isExpanded: true,
                      initialValue: _toAccountId,
                      decoration: const InputDecoration(
                          labelText: 'To',
                          helperText:
                              'A loan being repaid, a card bill, savings'),
                      items: [
                        ...accounts.map((a) => DropdownMenuItem<int?>(
                            value: a.id,
                            child:
                                Text(a.name, overflow: TextOverflow.ellipsis))),
                      ],
                      validator: (v) => v == null
                          ? 'Required'
                          : v == _accountId
                              ? 'Pick a different account'
                              : null,
                      onChanged: (v) => _toAccountId = v,
                    ),
                  if (!isSip)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ask me each time'),
                      subtitle: const Text(
                          'For a bill that differs: nothing is recorded '
                          'until you confirm the amount'),
                      value: _askFirst,
                      onChanged: (v) => setDialogState(() => _askFirst = v),
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
                  if (rule != null && rule.enabled)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        icon: const Icon(Icons.skip_next),
                        label: const Text('Skip the next one'),
                        onPressed: () {
                          Navigator.of(context).pop();
                          _skip(rule);
                        },
                      ),
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
                  _confirmDeleteRule(rule);
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
                    category: transfer() ? 'Transfer' : _category,
                    type: _type,
                    accountId: _accountId,
                    toAccountId: transfer() ? _toAccountId : null,
                    interval: _interval,
                    askFirst: !isSip && _askFirst,
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

  /// Passes over [rule]'s next occurrence, with an Undo.
  Future<void> _skip(RecurringRule rule) async {
    final provider = context.read<RecurringProvider>();
    final messenger = ScaffoldMessenger.of(context);
    await provider.skipOnce(rule);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
            'Skipped ${rule.description} for ${formatCompactDate(rule.nextDue)}'),
        action: SnackBarAction(
            label: 'Undo', onPressed: () => provider.updateRule(rule)),
      ));
  }

  /// Asks what an "ask me each time" rule came to and records it.
  Future<void> _confirmAmount(RecurringRule rule) async {
    final provider = context.read<RecurringProvider>();
    final expenses = context.read<ExpenseProvider>();
    final accounts = context.read<AccountProvider>();
    final investments = context.read<InvestmentProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final key = GlobalKey<FormState>();
    int? amount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(rule.description),
        content: Form(
          key: key,
          child: TextFormField(
            autofocus: true,
            initialValue:
                rule.amount == 0 ? '' : minorToEditString(rule.amount),
            decoration: InputDecoration(
                labelText: 'Amount this time',
                helperText: 'Due ${formatDateWithDay(rule.nextDue)}'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: validateAmountField,
            onSaved: (v) => amount = parseMinor(v ?? ''),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (!key.currentState!.validate()) return;
                key.currentState!.save();
                Navigator.pop(context, true);
              },
              child: const Text('Record')),
        ],
      ),
    );
    if (ok != true || amount == null) return;
    final posted = await provider.postOnce(rule, amount: amount);
    if (posted) {
      await expenses.reloadLoadedYears();
      await accounts.refreshBalances();
      if (rule.isInvestment) await investments.fetchInvestments();
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(posted
              ? 'Recorded ${rule.description}'
              : 'Pick both accounts for ${rule.description} first')));
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

  /// What a rule is for: its category, or the two accounts of a transfer.
  static String _what(BuildContext context, RecurringRule rule) {
    if (!rule.isTransfer) return rule.category;
    final accounts = context.watch<AccountProvider>();
    final from = accounts.accountById(rule.accountId)?.name ?? '?';
    final to = accounts.accountById(rule.toAccountId)?.name ?? '?';
    return '$from → $to';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      body: Consumer<RecurringProvider>(
        builder: (context, provider, _) {
          final rules = provider.rules;
          if (rules.isEmpty) {
            return EmptyState(
              icon: Icons.repeat,
              title: 'No recurring transactions',
              message:
                  'Add rent, salary, bills or a loan repayment and they post '
                  'automatically.',
              actionLabel: 'Add recurring',
              onAction: () => _showRuleDialog(),
            );
          }
          return ListView.separated(
            itemCount: rules.length,
            padding: scrollPadding(context, all: Space.md, fab: true),
            separatorBuilder: (_, __) => const SizedBox(height: Space.sm),
            itemBuilder: (context, index) {
              final rule = rules[index];
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
                    leading: rule.isTransfer
                        ? const CircleAvatar(child: Icon(Icons.swap_horiz))
                        : !rule.isInvestment &&
                                rule.type != DbConstants.txIncome
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
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${rule.isInvestment ? 'SIP · ' : ''}${_what(context, rule)} · ${rule.frequencyLabel} · next ${formatCompactDate(rule.nextDue)}'
                            '${rule.endDate != null ? ' · ends ${formatCompactDate(rule.endDate!)}' : ''}'),
                        // Nothing is recorded for these until confirmed.
                        if (rule.askFirst && rule.enabled)
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => _confirmAmount(rule),
                                child: const Text('Confirm amount'),
                              ),
                              TextButton(
                                onPressed: () => _skip(rule),
                                child: const Text('Skip'),
                              ),
                            ],
                          ),
                      ],
                    ),
                    trailing: Switch(
                      value: rule.enabled,
                      onChanged: (_) {
                        Haptics.light();
                        provider.toggleEnabled(rule);
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
