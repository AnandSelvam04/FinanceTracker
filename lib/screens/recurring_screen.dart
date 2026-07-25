import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/recurring_rule.dart';
import '../providers/account_provider.dart';
import '../providers/recurring_provider.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';
import '../utils/insets.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RecurringProvider>().fetchRules();
      context.read<AccountProvider>().fetchAccounts();
    });
  }

  Future<void> _showRuleDialog({RecurringRule? rule}) async {
    final l = AppLocalizations.of(context);
    _description = rule?.description ?? '';
    _amount = rule?.amount ?? 0;
    _category = rule?.category ?? '';
    _type = rule?.type ?? DbConstants.txExpense;
    _frequency = rule?.frequency ?? DbConstants.freqMonthly;
    _accountId = rule?.accountId;
    _nextDue = rule?.nextDue ?? DateTime.now();

    final accounts = context.read<AccountProvider>().accounts;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(rule == null ? l.addRecurring : l.editRecurring),
          content: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: _description,
                    decoration:
                        InputDecoration(labelText: l.description),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? l.fieldRequired : null,
                    onSaved: (v) => _description = v ?? '',
                  ),
                  TextFormField(
                    initialValue:
                        _amount == 0 ? '' : minorToEditString(_amount),
                    decoration: InputDecoration(labelText: l.amount),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) =>
                        double.tryParse(v ?? '') == null ? l.invalidValue : null,
                    onSaved: (v) => _amount = parseMinor(v ?? '0') ?? 0,
                  ),
                  TextFormField(
                    initialValue: _category,
                    decoration: InputDecoration(labelText: l.category),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? l.fieldRequired : null,
                    onSaved: (v) => _category = v ?? '',
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: InputDecoration(labelText: l.accountType),
                    items: [
                      DropdownMenuItem(
                          value: DbConstants.txExpense,
                          child: Text(l.expense)),
                      DropdownMenuItem(
                          value: DbConstants.txIncome, child: Text(l.income)),
                    ],
                    onChanged: (v) => _type = v ?? _type,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _frequency,
                    decoration:
                        InputDecoration(labelText: l.frequency),
                    items: RecurringRule.frequencies
                        .map((f) => DropdownMenuItem(
                            value: f, child: Text(l.freqLabel(f))))
                        .toList(),
                    onChanged: (v) => _frequency = v ?? _frequency,
                  ),
                  if (accounts.isNotEmpty)
                    DropdownButtonFormField<int?>(
                      initialValue: _accountId,
                      decoration:
                          InputDecoration(labelText: l.account),
                      items: [
                        DropdownMenuItem<int?>(
                            value: null, child: Text(l.none)),
                        ...accounts.map((a) => DropdownMenuItem<int?>(
                            value: a.id, child: Text(a.name))),
                      ],
                      onChanged: (v) => _accountId = v,
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                          child: Text(
                              '${l.nextDue}: ${l.dateWithDay(_nextDue)}')),
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
                        child: Text(l.change),
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
              child: Text(l.cancel),
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
              child: Text(rule == null ? l.add : l.save),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.recurring)),
      body: Consumer<RecurringProvider>(
        builder: (context, provider, _) {
          final rules = provider.rules;
          if (rules.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.repeat, size: 48, color: Colors.grey),
                    const SizedBox(height: 8),
                    Text(l.noRecurring),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: rules.length,
            padding: scrollPadding(context, all: 12, fab: true),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final rule = rules[index];
              return Card(
                elevation: 2,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: rule.type == DbConstants.txIncome
                        ? Colors.green.shade100
                        : Colors.red.shade50,
                    child: Icon(Icons.repeat,
                        color: rule.type == DbConstants.txIncome
                            ? Colors.green
                            : Colors.red),
                  ),
                  title: Text(rule.description,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '${rule.category} · ${l.freqLabel(rule.frequency)} · ${l.nextShort} ${l.dateWithDay(rule.nextDue)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formatMoneyRounded(rule.amount),
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      Switch(
                        value: rule.enabled,
                        onChanged: (_) => provider.toggleEnabled(rule),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        tooltip: l.deleteRule,
                        onPressed: () => provider.deleteRule(rule.id!),
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
        tooltip: l.addRecurringRule,
        onPressed: () => _showRuleDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
