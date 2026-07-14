import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/expense.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../services/backup_service.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';
import '../utils/transaction_filter.dart';

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

  // Advanced filters (set via the filter sheet).
  String? _categoryFilter;
  int? _accountFilter;
  double? _minAmount;
  double? _maxAmount;
  DateTimeRange? _dateRange;

  bool get _hasAdvancedFilters =>
      _categoryFilter != null ||
      _accountFilter != null ||
      _minAmount != null ||
      _maxAmount != null ||
      _dateRange != null;

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<bool> _confirmDelete(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text(
            'Remove "${expense.description}" for ${formatMoney(expense.amount)}?'),
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

  /// The current search/period/type plus advanced (category, account,
  /// amount range, custom date range) filters applied to a list.
  List<Expense> _applyFilters(List<Expense> all) {
    return TransactionFilter(
      searchQuery: _searchQuery,
      year: _selectedYear,
      month: _selectedMonth,
      type: _typeFilter,
      category: _categoryFilter,
      accountId: _accountFilter,
      minAmount: _minAmount,
      maxAmount: _maxAmount,
      startDate: _dateRange?.start,
      endDate: _dateRange?.end,
    ).apply(all);
  }

  Future<void> _openFilterSheet() async {
    final provider = context.read<ExpenseProvider>();
    final accounts = context.read<AccountProvider>().accounts;
    final categories = provider.expenses
        .map((e) => e.category)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    // Working copies so the sheet only applies on confirm.
    String? category = _categoryFilter;
    int? accountId = _accountFilter;
    final minController = TextEditingController(
        text: _minAmount == null ? '' : _minAmount!.toStringAsFixed(0));
    final maxController = TextEditingController(
        text: _maxAmount == null ? '' : _maxAmount!.toStringAsFixed(0));
    DateTimeRange? range = _dateRange;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Filters',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: categories.contains(category) ? category : null,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Any')),
                  ...categories.map((c) =>
                      DropdownMenuItem<String?>(value: c, child: Text(c))),
                ],
                onChanged: (v) => setSheet(() => category = v),
              ),
              if (accounts.isNotEmpty)
                DropdownButtonFormField<int?>(
                  initialValue: accounts.any((a) => a.id == accountId)
                      ? accountId
                      : null,
                  decoration: const InputDecoration(labelText: 'Account'),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('Any')),
                    ...accounts.map((a) => DropdownMenuItem<int?>(
                        value: a.id, child: Text(a.name))),
                  ],
                  onChanged: (v) => setSheet(() => accountId = v),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: minController,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Min amount'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: maxController,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Max amount'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(range == null
                        ? 'Date range: uses Year/Month above'
                        : 'Date range: ${_fmtRange(range!)}'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                        initialDateRange: range,
                      );
                      if (picked != null) setSheet(() => range = picked);
                    },
                    child: const Text('Pick'),
                  ),
                  if (range != null)
                    TextButton(
                      onPressed: () => setSheet(() => range = null),
                      child: const Text('Clear'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _categoryFilter = null;
                        _accountFilter = null;
                        _minAmount = null;
                        _maxAmount = null;
                        _dateRange = null;
                      });
                      Navigator.pop(context);
                    },
                    child: const Text('Reset all'),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _categoryFilter = category;
                        _accountFilter = accountId;
                        _minAmount =
                            double.tryParse(minController.text.trim());
                        _maxAmount =
                            double.tryParse(maxController.text.trim());
                        _dateRange = range;
                      });
                      Navigator.pop(context);
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtRange(DateTimeRange r) =>
      '${_formatDate(r.start)} → ${_formatDate(r.end)}';

  String get _filterLabel {
    final period = _selectedMonth == null
        ? '$_selectedYear'
        : '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}';
    return period;
  }

  /// Downloads exactly what the current filters show, via the share sheet.
  Future<void> _downloadFiltered() async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<ExpenseProvider>();
    final filtered = _applyFilters(provider.expenses);
    if (filtered.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nothing to download for this filter.')),
      );
      return;
    }
    try {
      final file = await writeExpensesCsvFile(
        filtered,
        filename: 'expenses_$_filterLabel.csv',
      );
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Finance Tracker — Transactions ($_filterLabel)',
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = List.generate(10, (i) => DateTime.now().year - i);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            icon: Icon(_hasAdvancedFilters
                ? Icons.filter_alt
                : Icons.filter_alt_outlined),
            tooltip: 'Filters',
            onPressed: _openFilterSheet,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Download filtered (CSV)',
            onPressed: _downloadFiltered,
          ),
        ],
      ),
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
                final expenses = _applyFilters(provider.expenses);
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
                                      ? '+${formatMoney(expense.amount)}'
                                      : expense.isTransfer
                                          ? formatMoney(expense.amount)
                                          : '-${formatMoney(expense.amount)}',
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
