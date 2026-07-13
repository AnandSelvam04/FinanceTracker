import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../models/expense.dart';
import '../utils/app_logger.dart';
import '../utils/db_constants.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<AccountProvider>();
      if (provider.accounts.isEmpty) {
        provider.fetchAccounts();
      }
    });
  }

  bool get _isIncome => _txType == DbConstants.txIncome;

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountProvider>().accounts;
    final categorySuggestions =
        _isIncome ? _incomeCategories : _expenseCategories;

    return Scaffold(
      appBar: AppBar(title: Text(_isIncome ? 'Add Income' : 'Add Expense')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
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
                decoration: const InputDecoration(labelText: 'Description'),
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    value!.isEmpty ? 'Enter a description' : null,
              ),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Amount'),
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
                    child:
                        Text('Date: ${_selectedDate.toString().split(' ')[0]}'),
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
                    child: const Text('Select Date'),
                  ),
                ],
              ),
              TextFormField(
                controller: _categoryController,
                decoration: InputDecoration(
                    labelText: _isIncome ? 'Source' : 'Category'),
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
                  decoration: const InputDecoration(labelText: 'Account'),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('None')),
                    ...accounts.map((a) =>
                        DropdownMenuItem<int?>(value: a.id, child: Text(a.name))),
                  ],
                  onChanged: (value) => setState(() => _accountId = value),
                ),
              if (!_isIncome)
                DropdownButtonFormField<String>(
                  initialValue: _selectedPaymentMode,
                  decoration: const InputDecoration(labelText: 'Payment Mode'),
                  items: _paymentModes
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedPaymentMode = value!),
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
                            amount: double.parse(_amountController.text),
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
                          try {
                            await provider.addExpense(expense);
                            await accountProvider.refreshBalances();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(_isIncome
                                        ? 'Income added'
                                        : 'Expense added')),
                              );
                              Navigator.pop(context);
                            }
                          } catch (e, st) {
                            // Show the error in a SnackBar and log
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text('Failed to save: $e'),
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
                    : Text(_isIncome ? 'Add Income' : 'Add Expense'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
