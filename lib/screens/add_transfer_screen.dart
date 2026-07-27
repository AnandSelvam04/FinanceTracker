import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../models/expense.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';
import '../utils/insets.dart';

class AddTransferScreen extends StatefulWidget {
  const AddTransferScreen({super.key});

  @override
  State<AddTransferScreen> createState() => _AddTransferScreenState();
}

class _AddTransferScreenState extends State<AddTransferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _toAmountController = TextEditingController();
  final _noteController = TextEditingController();
  int? _fromAccountId;
  int? _toAccountId;
  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _toAmountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Pre-fills the destination amount from the accounts' exchange rates so
  /// the user only has to adjust it when the actual rate differed.
  void _suggestToAmount(Account? from, Account? to) {
    if (from == null || to == null || to.rate == 0) return;
    final amount = double.tryParse(_amountController.text);
    if (amount == null) return;
    final received = amount * from.rate / to.rate;
    _toAmountController.text = received.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final accountProvider = context.watch<AccountProvider>();
    final accounts = accountProvider.accounts;
    final fromAccount = accountProvider.accountById(_fromAccountId);
    final toAccount = accountProvider.accountById(_toAccountId);
    // A second, destination-currency amount is only needed when the two
    // accounts are held in different currencies.
    final crossCurrency = fromAccount != null &&
        toAccount != null &&
        fromAccount.symbol != toAccount.symbol;

    return Scaffold(
      appBar: AppBar(title: const Text('Transfer between accounts')),
      body: accounts.length < 2
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: const Text('You need at least two accounts to record a transfer.'),
              ),
            )
          : SingleChildScrollView(
              padding: scrollPadding(context),
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
                      onChanged: (v) {
                        setState(() => _fromAccountId = v);
                        _suggestToAmount(
                            accountProvider.accountById(v), toAccount);
                      },
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
                      onChanged: (v) {
                        setState(() => _toAccountId = v);
                        _suggestToAmount(
                            fromAccount, accountProvider.accountById(v));
                      },
                    ),
                    TextFormField(
                      controller: _amountController,
                      decoration: InputDecoration(
                        labelText: crossCurrency
                            ? 'Amount (${fromAccount.symbol})'
                            : 'Amount',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) {
                        if (crossCurrency) {
                          _suggestToAmount(fromAccount, toAccount);
                        }
                      },
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
                    if (crossCurrency)
                      TextFormField(
                        controller: _toAmountController,
                        decoration: InputDecoration(
                          labelText:
                              'Amount received (${toAccount.symbol})',
                          helperText:
                              '${fromAccount.symbol} → ${toAccount.symbol}',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
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
    final accountProvider0 = context.read<AccountProvider>();
    final from = accountProvider0.accountById(_fromAccountId);
    final to = accountProvider0.accountById(_toAccountId);
    final crossCurrency =
        from != null && to != null && from.symbol != to.symbol;
    final transfer = Expense(
      description: note.isEmpty ? 'Transfer' : note,
      amount: rupeesToMinor(double.parse(_amountController.text)),
      date: _selectedDate,
      category: 'Transfer',
      paymentMode: 'Other',
      type: DbConstants.txTransfer,
      accountId: _fromAccountId,
      toAccountId: _toAccountId,
      // Destination-currency amount, only for cross-currency transfers.
      toAmount: crossCurrency
          ? rupeesToMinor(double.parse(_toAmountController.text))
          : null,
    );
    final expenseProvider = context.read<ExpenseProvider>();
    final accountProvider = context.read<AccountProvider>();
    try {
      await expenseProvider.addExpense(transfer);
      await accountProvider.refreshBalances();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Transfer recorded')),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
