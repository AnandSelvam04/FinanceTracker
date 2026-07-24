import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/app_localizations.dart';
import '../models/expense.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../services/backup_service.dart';
import '../services/db_service.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
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

  /// Year of the earliest recorded transaction, so the year filter reaches
  /// all data instead of a hardcoded last-10-years window.
  int _earliestYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final bounds = await DBService().transactionYearBounds();
      if (bounds != null && mounted) {
        setState(() => _earliestYear = bounds.$1);
      }
    });
  }

  /// Loads the data needed to show [year] (the provider only holds the years
  /// it has been asked for).
  Future<void> _selectYear(int year) async {
    setState(() => _selectedYear = year);
    await context.read<ExpenseProvider>().ensureYearLoaded(year);
  }

  // Advanced filters (set via the filter sheet).
  String? _categoryFilter;
  int? _accountFilter;
  int? _minAmount; // minor units
  int? _maxAmount; // minor units
  DateTimeRange? _dateRange;

  bool get _hasAdvancedFilters =>
      _categoryFilter != null ||
      _accountFilter != null ||
      _minAmount != null ||
      _maxAmount != null ||
      _dateRange != null;

  Future<bool> _confirmDelete(Expense expense) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.deleteExpenseTitle),
        content: Text(l.deleteExpenseBody(
            expense.description, formatMoney(expense.amount))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel)),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.delete)),
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
    final l = AppLocalizations.of(context);
    final descController = TextEditingController(text: expense.description);
    final amountController =
        TextEditingController(text: minorToEditString(expense.amount));
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
                Text(l.editExpense,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: InputDecoration(labelText: l.description),
                ),
                TextField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: l.amount),
                ),
                TextField(
                  controller: categoryController,
                  decoration: InputDecoration(labelText: l.category),
                ),
                DropdownButtonFormField<String>(
                  initialValue: paymentMode,
                  decoration: InputDecoration(labelText: l.paymentMode),
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
                    Text('${l.date}: ${l.dateWithDay(selectedDate)}'),
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
                      child: Text(l.change),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final amount =
                          parseMinor(amountController.text.trim());
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
                    child: Text(l.save),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Future<void> _editTransfer(Expense transfer) async {
    final l = AppLocalizations.of(context);
    final accountProvider0 = context.read<AccountProvider>();
    final accounts = accountProvider0.accounts;
    final amountController =
        TextEditingController(text: minorToEditString(transfer.amount));
    final toAmountController = TextEditingController(
        text: minorToEditString(transfer.receivedAmount));
    final noteController = TextEditingController(text: transfer.description);
    int? fromId = transfer.accountId;
    int? toId = transfer.toAccountId;
    DateTime date = transfer.date;

    bool crossCurrency() {
      final from = accountProvider0.accountById(fromId);
      final to = accountProvider0.accountById(toId);
      return from != null && to != null && from.symbol != to.symbol;
    }

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
            children: [
              Text(l.editTransfer,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: accounts.any((a) => a.id == fromId) ? fromId : null,
                decoration: InputDecoration(labelText: l.fromAccount),
                items: accounts
                    .map((a) =>
                        DropdownMenuItem<int?>(value: a.id, child: Text(a.name)))
                    .toList(),
                onChanged: (v) => setSheet(() => fromId = v),
              ),
              DropdownButtonFormField<int?>(
                initialValue: accounts.any((a) => a.id == toId) ? toId : null,
                decoration: InputDecoration(labelText: l.toAccount),
                items: accounts
                    .map((a) =>
                        DropdownMenuItem<int?>(value: a.id, child: Text(a.name)))
                    .toList(),
                onChanged: (v) => setSheet(() => toId = v),
              ),
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: l.amount),
              ),
              if (crossCurrency())
                TextField(
                  controller: toAmountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText:
                        '${l.amountReceived} (${accountProvider0.accountById(toId)!.symbol})',
                  ),
                ),
              TextField(
                controller: noteController,
                decoration: InputDecoration(labelText: l.note),
              ),
              Row(
                children: [
                  Text('${l.date}: ${l.dateWithDay(date)}'),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setSheet(() => date = picked);
                    },
                    child: Text(l.change),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final amount = parseMinor(amountController.text.trim());
                    if (amount == null || fromId == null || toId == null ||
                        fromId == toId) {
                      return;
                    }
                    int? toAmount;
                    if (crossCurrency()) {
                      toAmount = parseMinor(toAmountController.text.trim());
                      if (toAmount == null) return;
                    }
                    final updated = Expense(
                      id: transfer.id,
                      description: noteController.text.trim().isEmpty
                          ? 'Transfer'
                          : noteController.text.trim(),
                      amount: amount,
                      date: date,
                      category: 'Transfer',
                      paymentMode: 'Other',
                      type: DbConstants.txTransfer,
                      accountId: fromId,
                      toAccountId: toId,
                      toAmount: toAmount,
                    );
                    final expenseProvider = context.read<ExpenseProvider>();
                    final accountProvider = context.read<AccountProvider>();
                    await expenseProvider.updateExpense(updated);
                    await accountProvider.refreshBalances();
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
                  child: Text(l.save),
                ),
              ),
            ],
          ),
        ),
      ),
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
    final l = AppLocalizations.of(context);
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
        text: _minAmount == null ? '' : minorToEditString(_minAmount!));
    final maxController = TextEditingController(
        text: _maxAmount == null ? '' : minorToEditString(_maxAmount!));
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
              Text(l.filters,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: categories.contains(category) ? category : null,
                decoration: InputDecoration(labelText: l.category),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(l.any)),
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
                  decoration: InputDecoration(labelText: l.account),
                  items: [
                    DropdownMenuItem<int?>(value: null, child: Text(l.any)),
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
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: l.minAmount),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: maxController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: l.maxAmount),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(range == null
                        ? l.dateRangeUsesYearMonth
                        : l.dateRangeIs(_fmtRange(range!))),
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
                    child: Text(l.pick),
                  ),
                  if (range != null)
                    TextButton(
                      onPressed: () => setSheet(() => range = null),
                      child: Text(l.clear),
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
                    child: Text(l.resetAll),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      final appliedRange = range;
                      setState(() {
                        _categoryFilter = category;
                        _accountFilter = accountId;
                        _minAmount = parseMinor(minController.text.trim());
                        _maxAmount = parseMinor(maxController.text.trim());
                        _dateRange = appliedRange;
                      });
                      // A custom range can span years the provider hasn't
                      // loaded yet; load them so the filter shows everything.
                      if (appliedRange != null) {
                        context.read<ExpenseProvider>().ensureYearsLoaded([
                          for (var y = appliedRange.start.year;
                              y <= appliedRange.end.year;
                              y++)
                            y
                        ]);
                      }
                      Navigator.pop(context);
                    },
                    child: Text(l.apply),
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
      '${formatIsoDate(r.start)} → ${formatIsoDate(r.end)}';

  String get _filterLabel {
    final period = _selectedMonth == null
        ? '$_selectedYear'
        : '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}';
    return period;
  }

  /// Downloads exactly what the current filters show, via the share sheet.
  Future<void> _downloadFiltered() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<ExpenseProvider>();
    final filtered = _applyFilters(provider.expenses);
    if (filtered.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.nothingToDownload)),
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
        subject: 'Finance Tracker — ${l.transactions} ($_filterLabel)',
      );
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(l.errorWithDetails('$e'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final currentYear = DateTime.now().year;
    // Every year from the earliest transaction to now, newest first, so old
    // data stays reachable (the list used to stop at 10 years back).
    final firstYear =
        _earliestYear < currentYear ? _earliestYear : currentYear;
    final years = [
      for (var y = currentYear; y >= firstYear; y--) y,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l.transactions),
        actions: [
          IconButton(
            icon: Icon(_hasAdvancedFilters
                ? Icons.filter_alt
                : Icons.filter_alt_outlined),
            tooltip: l.filters,
            onPressed: _openFilterSheet,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: l.downloadFilteredCsv,
            onPressed: _downloadFiltered,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                labelText: l.searchExpenses,
                prefixIcon: const Icon(Icons.search),
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
              Text('${l.year}:'),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _selectedYear,
                items: years
                    .map((y) => DropdownMenuItem(
                          value: y,
                          child: Text(y.toString()),
                        ))
                    .toList(),
                onChanged: (y) {
                  if (y != null) _selectYear(y);
                },
              ),
              const SizedBox(width: 16),
              Text('${l.month}:'),
              const SizedBox(width: 8),
              DropdownButton<int?>(
                value: _selectedMonth,
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(l.all),
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
                for (final entry in [
                  (null, l.all),
                  (DbConstants.txExpense, l.navExpenses),
                  (DbConstants.txIncome, l.income),
                  (DbConstants.txTransfer, l.transfers),
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
                      children: [
                        const Icon(Icons.inbox, size: 48, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text(l.noExpensesFound),
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
                                ? incomeAvatarColor(context)
                                : expense.isTransfer
                                    ? transferAvatarColor(context)
                                    : expenseAvatarColor(context),
                            child: expense.isTransfer
                                ? Icon(Icons.swap_horiz,
                                    color: transferColor(context))
                                : Text(expense.category.isNotEmpty
                                    ? expense.category[0].toUpperCase()
                                    : '?'),
                          ),
                          title: Text(expense.description,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${expense.category} · ${l.dateWithDay(expense.date)}'),
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
                                          ? incomeColor(context)
                                          : expense.isTransfer
                                              ? transferColor(context)
                                              : expenseColor(context))),
                              const SizedBox(height: 4),
                              Text(
                                  expense.isExpense
                                      ? expense.paymentMode
                                      : expense.isIncome
                                          ? l.income
                                          : l.transfer,
                                  style: TextStyle(
                                      color: mutedTextColor(context),
                                      fontSize: 12)),
                            ],
                          ),
                          onTap: () => expense.isTransfer
                              ? _editTransfer(expense)
                              : _editExpense(expense),
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
