import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/recurring_rule.dart';
import '../providers/account_provider.dart';
import '../providers/recurring_provider.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';
import '../utils/insets.dart';
import '../utils/date_format.dart';
import '../widgets/empty_state.dart';

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
      context.read<RecurringProvider>().fetchRules();
      context.read<AccountProvider>().fetchAccounts();
    });
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

  Future<void> _showRuleDialog({RecurringRule? rule}) async {
    _description = rule?.description ?? '';
    _amount = rule?.amount ?? 0;
    _category = rule?.category ?? '';
    _type = rule?.type ?? DbConstants.txExpense;
    _frequency = rule?.frequency ?? DbConstants.freqMonthly;
    _accountId = rule?.accountId;
    _nextDue = rule?.nextDue ?? DateTime.now();
    _endDate = rule?.endDate;

    final accounts = context.read<AccountProvider>().accounts;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(rule == null ? 'Add Recurring' : 'Edit Recurring'),
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
                    decoration: const InputDecoration(labelText: 'Category'),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                    onSaved: (v) => _category = v ?? '',
                  ),
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
                      initialValue: _accountId,
                      decoration: const InputDecoration(labelText: 'Account'),
                      items: [
                        DropdownMenuItem<int?>(
                            value: null, child: const Text('None')),
                        ...accounts.map((a) => DropdownMenuItem<int?>(
                            value: a.id, child: Text(a.name))),
                      ],
                      onChanged: (v) => _accountId = v,
                    ),
                  const SizedBox(height: 8),
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
                            setDialogState(() => _nextDue = picked);
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
                            initialDate: _endDate ?? _nextDue,
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
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
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
                    enabled: rule?.enabled ?? true,
                    endDate: _endDate,
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
          ElevatedButton(
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
          final rules = provider.rules;
          if (rules.isEmpty) {
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
            itemCount: rules.length,
            padding: scrollPadding(context, all: 12, fab: true),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final rule = rules[index];
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: rule.type == DbConstants.txIncome
                        ? incomeAvatarColor(context)
                        : expenseAvatarColor(context),
                    child: Icon(Icons.repeat,
                        color: rule.type == DbConstants.txIncome
                            ? incomeColor(context)
                            : expenseColor(context)),
                  ),
                  title: Text(rule.description,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '${rule.category} · ${_freqLabel(rule.frequency)} · next ${formatDateWithDay(rule.nextDue)}'
                      '${rule.endDate != null ? ' · ends ${formatDateWithDay(rule.endDate!)}' : ''}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formatMoneyRounded(rule.amount),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Switch(
                        value: rule.enabled,
                        onChanged: (_) => provider.toggleEnabled(rule),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        tooltip: 'Delete rule',
                        onPressed: () => _confirmDeleteRule(rule),
                      ),
                    ],
                  ),
                  onTap: () => _showRuleDialog(rule: rule),
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
