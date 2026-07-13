import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../utils/db_constants.dart';

class ExpenseListScreen extends StatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  State<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends State<ExpenseListScreen> {
  String _searchQuery = '';
  int _selectedYear = DateTime.now().year;
  int? _selectedMonth = DateTime.now().month;
  String? _typeFilter;

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<bool> _confirmDelete(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text(
            'Remove "${expense.description}" for ₹${expense.amount.toStringAsFixed(2)}?'),
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
    if (confirmed == true) {
      // ignore: use_build_context_synchronously
      await context.read<ExpenseProvider>().deleteExpense(expense.id!);
      if (mounted) {
        await context.read<AccountProvider>().refreshBalances();
      }
      return true;
    }
    return false;
  }

  Future<void> _editExpense(Expense expense) async {
    final descController = TextEditingController(text: expense.description);
    final amountController =
        TextEditingController(text: expense.amount.toStringAsFixed(2));
    final categoryController = TextEditingController(text: expense.category);
    String paymentMode = expense.paymentMode;
    DateTime selectedDate = expense.date;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Edit Expense',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
                TextField(
                  controller: categoryController,
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: paymentMode,
                  decoration: const InputDecoration(labelText: 'Payment Mode'),
                  items: const [
                    DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                    DropdownMenuItem(
                        value: 'Credit Card', child: Text('Credit Card')),
                    DropdownMenuItem(
                        value: 'Debit Card', child: Text('Debit Card')),
                    DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (v) =>
                      setModalState(() => paymentMode = v ?? paymentMode),
                ),
                Row(
                  children: [
                    Text('Date: ${_formatDate(selectedDate)}'),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setModalState(() => selectedDate = picked);
                        }
                      },
                      child: const Text('Change'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final amount =
                          double.tryParse(amountController.text.trim());
                      if (amount == null) return;
                      final updated = Expense(
                        id: expense.id,
                        description: descController.text.trim(),
                        amount: amount,
                        date: selectedDate,
                        category: categoryController.text.trim(),
                        paymentMode: paymentMode,
                        type: expense.type,
                        accountId: expense.accountId,
                        toAccountId: expense.toAccountId,
                      );
                      final provider = context.read<ExpenseProvider>();
                      final accountProvider = context.read<AccountProvider>();
                      await provider.updateExpense(updated);
                      await accountProvider.refreshBalances();
                      if (!context.mounted) return;
                      Navigator.pop(context);
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final years = List.generate(10, (i) => DateTime.now().year - i);

    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search Expenses',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Year:'),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _selectedYear,
                items: years
                    .map((y) => DropdownMenuItem(
                          value: y,
                          child: Text(y.toString()),
                        ))
                    .toList(),
                onChanged: (y) => setState(() => _selectedYear = y!),
              ),
              const SizedBox(width: 16),
              const Text('Month:'),
              const SizedBox(width: 8),
              DropdownButton<int?>(
                value: _selectedMonth,
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text('All'),
                  ),
                  ...List.generate(
                      12,
                      (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text('${i + 1}'),
                          ))
                ],
                onChanged: (m) => setState(() => _selectedMonth = m),
              ),
            ],
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final entry in const [
                  (null, 'All'),
                  (DbConstants.txExpense, 'Expenses'),
                  (DbConstants.txIncome, 'Income'),
                  (DbConstants.txTransfer, 'Transfers'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.$2),
                      selected: _typeFilter == entry.$1,
                      onSelected: (_) =>
                          setState(() => _typeFilter = entry.$1),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Consumer<ExpenseProvider>(
              builder: (context, provider, _) {
                final expenses = provider.expenses.where((e) {
                  final matchesSearch =
                      e.description.toLowerCase().contains(_searchQuery) ||
                          e.category.toLowerCase().contains(_searchQuery);
                  final matchesYear = e.date.year == _selectedYear;
                  final matchesMonth =
                      _selectedMonth == null || e.date.month == _selectedMonth;
                  final matchesType =
                      _typeFilter == null || e.type == _typeFilter;
                  return matchesSearch &&
                      matchesYear &&
                      matchesMonth &&
                      matchesType;
                }).toList();
                if (expenses.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.inbox, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('No expenses found.'),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: expenses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  padding: const EdgeInsets.all(12),
                  itemBuilder: (context, index) {
                    final expense = expenses[index];
                    return Dismissible(
                      key: ValueKey(
                          expense.id ?? '${expense.description}-$index'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        color: Colors.red.shade400,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (_) => _confirmDelete(expense),
                      child: Card(
                        elevation: 2,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: expense.isIncome
                                ? Colors.green.shade100
                                : expense.isTransfer
                                    ? Colors.blueGrey.shade100
                                    : Colors.red.shade50,
                            child: expense.isTransfer
                                ? const Icon(Icons.swap_horiz,
                                    color: Colors.blueGrey)
                                : Text(expense.category.isNotEmpty
                                    ? expense.category[0].toUpperCase()
                                    : '?'),
                          ),
                          title: Text(expense.description,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${expense.category} · ${_formatDate(expense.date)}'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                  expense.isIncome
                                      ? '+₹${expense.amount.toStringAsFixed(2)}'
                                      : expense.isTransfer
                                          ? '₹${expense.amount.toStringAsFixed(2)}'
                                          : '-₹${expense.amount.toStringAsFixed(2)}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: expense.isIncome
                                          ? Colors.green.shade700
                                          : expense.isTransfer
                                              ? Colors.blueGrey
                                              : Colors.red.shade700)),
                              const SizedBox(height: 4),
                              Text(
                                  expense.isExpense
                                      ? expense.paymentMode
                                      : expense.isIncome
                                          ? 'Income'
                                          : 'Transfer',
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12)),
                            ],
                          ),
                          onTap: () => _editExpense(expense),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
