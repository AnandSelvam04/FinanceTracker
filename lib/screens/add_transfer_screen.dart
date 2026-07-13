import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../utils/db_constants.dart';

class AddTransferScreen extends StatefulWidget {
  const AddTransferScreen({super.key});

  @override
  State<AddTransferScreen> createState() => _AddTransferScreenState();
}

class _AddTransferScreenState extends State<AddTransferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  int? _fromAccountId;
  int? _toAccountId;
  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountProvider>().accounts;

    return Scaffold(
      appBar: AppBar(title: const Text('Transfer Between Accounts')),
      body: accounts.length < 2
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'You need at least two accounts to record a transfer.'),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: _fromAccountId,
                      decoration:
                          const InputDecoration(labelText: 'From account'),
                      items: accounts
                          .map((a) => DropdownMenuItem(
                              value: a.id, child: Text(a.name)))
                          .toList(),
                      validator: (v) => v == null ? 'Select an account' : null,
                      onChanged: (v) => setState(() => _fromAccountId = v),
                    ),
                    DropdownButtonFormField<int>(
                      initialValue: _toAccountId,
                      decoration:
                          const InputDecoration(labelText: 'To account'),
                      items: accounts
                          .map((a) => DropdownMenuItem(
                              value: a.id, child: Text(a.name)))
                          .toList(),
                      validator: (v) {
                        if (v == null) return 'Select an account';
                        if (v == _fromAccountId) {
                          return 'Must differ from source account';
                        }
                        return null;
                      },
                      onChanged: (v) => setState(() => _toAccountId = v),
                    ),
                    TextFormField(
                      controller: _amountController,
                      decoration: const InputDecoration(labelText: 'Amount'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Enter an amount';
                        }
                        final amount = double.tryParse(value);
                        if (amount == null || amount <= 0) {
                          return 'Enter a valid amount';
                        }
                        return null;
                      },
                    ),
                    TextFormField(
                      controller: _noteController,
                      decoration:
                          const InputDecoration(labelText: 'Note (optional)'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                              'Date: ${_selectedDate.toString().split(' ')[0]}'),
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
                              setState(() => _selectedDate = picked);
                            }
                          },
                          child: const Text('Select Date'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : () => _save(context),
                        child: _isSaving
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : const Text('Record Transfer'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _save(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final note = _noteController.text.trim();
    final transfer = Expense(
      description: note.isEmpty ? 'Transfer' : note,
      amount: double.parse(_amountController.text),
      date: _selectedDate,
      category: 'Transfer',
      paymentMode: 'Other',
      type: DbConstants.txTransfer,
      accountId: _fromAccountId,
      toAccountId: _toAccountId,
    );
    final expenseProvider = context.read<ExpenseProvider>();
    final accountProvider = context.read<AccountProvider>();
    try {
      await expenseProvider.addExpense(transfer);
      await accountProvider.refreshBalances();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transfer recorded')),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
