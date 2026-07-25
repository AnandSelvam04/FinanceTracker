import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/template_provider.dart';
import '../models/expense.dart';
import '../models/tx_template.dart';
import '../services/db_service.dart';
import '../utils/app_logger.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';
import '../utils/insets.dart';

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String _selectedPaymentMode = 'Cash';
  String _txType = DbConstants.txExpense;
  int? _accountId;
  bool _isSaving = false;
  bool _saveAsTemplate = false;
  List<String> _frequentExpenseCategories = const [];
  List<String> _frequentIncomeCategories = const [];

  final List<String> _expenseCategories = const [
    'Food',
    'Transport',
    'Shopping',
    'Bills',
    'Entertainment',
    'Health',
    'Education',
    'Other',
  ];

  final List<String> _incomeCategories = const [
    'Salary',
    'Business',
    'Interest',
    'Dividends',
    'Gift',
    'Refund',
    'Other',
  ];

  final List<String> _paymentModes = [
    'Cash',
    'Credit Card',
    'Debit Card',
    'UPI',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<AccountProvider>();
      if (provider.accounts.isEmpty) {
        provider.fetchAccounts();
      }
      // Preselect the user's default account, if set and still present.
      final defaultId = context.read<SettingsProvider>().defaultAccountId;
      if (defaultId != null &&
          context.read<AccountProvider>().accountById(defaultId) != null) {
        setState(() => _accountId = defaultId);
      }
      final expenseFreq =
          await DBService().frequentCategories(DbConstants.txExpense);
      final incomeFreq =
          await DBService().frequentCategories(DbConstants.txIncome);
      if (mounted) {
        setState(() {
          _frequentExpenseCategories = expenseFreq;
          _frequentIncomeCategories = incomeFreq;
        });
      }
    });
  }

  bool get _isIncome => _txType == DbConstants.txIncome;

  /// Recent categories first, then built-in defaults, de-duplicated.
  List<String> get _suggestions {
    final frequent =
        _isIncome ? _frequentIncomeCategories : _frequentExpenseCategories;
    final defaults = _isIncome ? _incomeCategories : _expenseCategories;
    return <String>{...frequent, ...defaults}.toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final accounts = context.watch<AccountProvider>().accounts;
    final categorySuggestions = _suggestions;

    return Scaffold(
      appBar: AppBar(title: Text(_isIncome ? l.addIncome : l.addExpense)),
      body: SingleChildScrollView(
        padding: scrollPadding(context),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: DbConstants.txExpense,
                      label: Text(l.expense),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    ButtonSegment(
                      value: DbConstants.txIncome,
                      label: Text(l.income),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                  selected: {_txType},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _txType = selection.first;
                      _categoryController.clear();
                    });
                  },
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(labelText: l.description),
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    value!.isEmpty ? 'Enter a description' : null,
              ),
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(labelText: l.amount),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value!.isEmpty) return 'Enter an amount';
                  final amount = double.tryParse(value);
                  if (amount == null || amount <= 0) {
                    return 'Enter a valid amount';
                  }
                  return null;
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                        '${l.date}: ${_selectedDate.toString().split(' ')[0]}'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() {
                          _selectedDate = picked;
                        });
                      }
                    },
                    child: Text(l.selectDate),
                  ),
                ],
              ),
              TextFormField(
                controller: _categoryController,
                decoration: InputDecoration(
                    labelText: _isIncome ? l.source : l.category),
                textInputAction: TextInputAction.next,
                validator: (value) => value!.isEmpty
                    ? (_isIncome ? 'Enter a source' : 'Enter a category')
                    : null,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: categorySuggestions
                    .map((c) => ChoiceChip(
                          label: Text(c),
                          selected: _categoryController.text == c,
                          onSelected: (_) {
                            setState(() {
                              _categoryController.text = c;
                            });
                          },
                        ))
                    .toList(),
              ),
              if (accounts.isNotEmpty)
                DropdownButtonFormField<int?>(
                  initialValue: _accountId,
                  decoration: InputDecoration(labelText: l.account),
                  items: [
                    DropdownMenuItem<int?>(
                        value: null, child: Text(l.none)),
                    ...accounts.map((a) =>
                        DropdownMenuItem<int?>(value: a.id, child: Text(a.name))),
                  ],
                  onChanged: (value) => setState(() => _accountId = value),
                ),
              if (!_isIncome)
                DropdownButtonFormField<String>(
                  initialValue: _selectedPaymentMode,
                  decoration: InputDecoration(labelText: l.paymentMode),
                  items: _paymentModes
                      .map((p) => DropdownMenuItem(
                          value: p, child: Text(l.paymentModeLabel(p))))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedPaymentMode = value!),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l.saveAsTemplate),
                value: _saveAsTemplate,
                onChanged: (v) =>
                    setState(() => _saveAsTemplate = v ?? false),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isSaving
                    ? null
                    : () async {
                        if (_formKey.currentState!.validate()) {
                          setState(() => _isSaving = true);
                          final expense = Expense(
                            description: _descriptionController.text,
                            amount: rupeesToMinor(
                                double.parse(_amountController.text)),
                            date: _selectedDate,
                            category: _categoryController.text,
                            paymentMode:
                                _isIncome ? 'Other' : _selectedPaymentMode,
                            type: _txType,
                            accountId: _accountId,
                          );
                          final provider = context.read<ExpenseProvider>();
                          final accountProvider =
                              context.read<AccountProvider>();
                          final templateProvider =
                              context.read<TemplateProvider>();
                          try {
                            await provider.addExpense(expense);
                            await accountProvider.refreshBalances();
                            if (_saveAsTemplate) {
                              await templateProvider.addTemplate(TxTemplate(
                                name: _descriptionController.text,
                                description: _descriptionController.text,
                                amount: rupeesToMinor(
                                    double.parse(_amountController.text)),
                                category: _categoryController.text,
                                type: _txType,
                                accountId: _accountId,
                              ));
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(_isIncome
                                        ? l.incomeAdded
                                        : l.expenseAdded)),
                              );
                              Navigator.pop(context);
                            }
                          } catch (e, st) {
                            // Show the error in a SnackBar and log
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text(l.failedToSave('$e')),
                              ));
                            }
                            AppLogger.error('Error saving expense', e, st);
                          } finally {
                            if (mounted) setState(() => _isSaving = false);
                          }
                        }
                      },
                child: _isSaving
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                      )
                    : Text(_isIncome ? l.addIncome : l.addExpense),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
