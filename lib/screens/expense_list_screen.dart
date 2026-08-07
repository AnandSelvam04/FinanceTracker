import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/expense.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../services/backup_service.dart';
import '../services/db_service.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/db_constants.dart';
import '../utils/insets.dart';
import '../utils/transaction_filter.dart';
import '../widgets/empty_state.dart';
import '../widgets/skeleton.dart';

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

  /// Lower bound for the date pickers. Hardcoding the year 2000 made rows
  /// imported from older statements impossible to edit or range-filter; this
  /// tracks the earliest transaction actually present, with a year of slack.
  DateTime get _pickerFirstDate => DateTime(_earliestYear - 1);

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

  /// A row's amount in the currency it was actually recorded in.
  ///
  /// Amounts are stored in their source account's currency, so formatting them
  /// with the base symbol labelled a $100 expense as "₹100.00". Rows with no
  /// account fall back to the base symbol, which is what they are.
  String _rowAmount(BuildContext context, Expense expense) {
    final account =
        context.read<AccountProvider>().accountById(expense.accountId);
    return account == null
        ? formatMoney(expense.amount)
        : formatMoneyIn(account.symbol, expense.amount);
  }

  Future<bool> _confirmDelete(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text('Remove "${expense.description}" for '
            '${formatMoney(expense.amount)}?'),
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
        TextEditingController(text: minorToEditString(expense.amount));
    final categoryController = TextEditingController(text: expense.category);
    String paymentMode = expense.paymentMode;
    DateTime selectedDate = expense.date;

    // The sheet owns these controllers for its lifetime; dispose them once
    // it closes rather than leaking one set per open/close cycle.
    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) {
          return StatefulBuilder(builder: (context, setModalState) {
            return Padding(
              padding: bottomSheetPadding(context),
              // Scrollable so the form can still be reached (and Save tapped)
              // when the keyboard shrinks the available height.
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Edit Expense',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      decoration:
                          const InputDecoration(labelText: 'Description'),
                    ),
                    TextField(
                      controller: amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Amount'),
                    ),
                    TextField(
                      controller: categoryController,
                      decoration: const InputDecoration(labelText: 'Category'),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: paymentMode,
                      decoration:
                          const InputDecoration(labelText: 'Payment Mode'),
                      items: [
                        DropdownMenuItem(
                            value: 'Cash', child: const Text('Cash')),
                        DropdownMenuItem(
                            value: 'Credit Card',
                            child: const Text('Credit Card')),
                        DropdownMenuItem(
                            value: 'Debit Card',
                            child: const Text('Debit Card')),
                        DropdownMenuItem(
                            value: 'UPI', child: const Text('UPI')),
                        DropdownMenuItem(
                            value: 'Other', child: const Text('Other')),
                      ],
                      onChanged: (v) =>
                          setModalState(() => paymentMode = v ?? paymentMode),
                    ),
                    Row(
                      children: [
                        Text('Date: ${formatDateWithDay(selectedDate)}'),
                        const Spacer(),
                        TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: _pickerFirstDate,
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
                      height: kSheetActionHeight,
                      child: ElevatedButton(
                        onPressed: () async {
                          // Say why nothing happened. Returning silently made
                          // Save look like a dead button.
                          final problem =
                              validateAmountField(amountController.text);
                          if (problem != null) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(problem)));
                            return;
                          }
                          final amount =
                              parseMinor(amountController.text.trim())!;
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
                          final accountProvider =
                              context.read<AccountProvider>();
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
              ),
            );
          });
        },
      );
    } finally {
      descController.dispose();
      amountController.dispose();
      categoryController.dispose();
    }
  }

  Future<void> _editTransfer(Expense transfer) async {
    final accountProvider0 = context.read<AccountProvider>();
    final accounts = accountProvider0.accounts;
    final amountController =
        TextEditingController(text: minorToEditString(transfer.amount));
    final toAmountController =
        TextEditingController(text: minorToEditString(transfer.receivedAmount));
    final noteController = TextEditingController(text: transfer.description);
    int? fromId = transfer.accountId;
    int? toId = transfer.toAccountId;
    DateTime date = transfer.date;

    bool crossCurrency() {
      final from = accountProvider0.accountById(fromId);
      final to = accountProvider0.accountById(toId);
      return from != null && to != null && from.symbol != to.symbol;
    }

    // The sheet owns these controllers for its lifetime; dispose them once
    // it closes rather than leaking one set per open/close cycle.
    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) => StatefulBuilder(
          builder: (context, setSheet) => Padding(
            padding: bottomSheetPadding(context),
            // Scrollable so the form can still be reached (and Save tapped)
            // when the keyboard shrinks the available height.
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Edit Transfer',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue:
                        accounts.any((a) => a.id == fromId) ? fromId : null,
                    decoration:
                        const InputDecoration(labelText: 'From account'),
                    items: accounts
                        .map((a) => DropdownMenuItem<int?>(
                            value: a.id, child: Text(a.name)))
                        .toList(),
                    onChanged: (v) => setSheet(() => fromId = v),
                  ),
                  DropdownButtonFormField<int?>(
                    initialValue:
                        accounts.any((a) => a.id == toId) ? toId : null,
                    decoration: const InputDecoration(labelText: 'To account'),
                    items: accounts
                        .map((a) => DropdownMenuItem<int?>(
                            value: a.id, child: Text(a.name)))
                        .toList(),
                    onChanged: (v) => setSheet(() => toId = v),
                  ),
                  TextField(
                    controller: amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                  if (crossCurrency())
                    TextField(
                      controller: toAmountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText:
                            'Amount received (${accountProvider0.accountById(toId)!.symbol})',
                      ),
                    ),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: 'Note'),
                  ),
                  Row(
                    children: [
                      Text('Date: ${formatDateWithDay(date)}'),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: date,
                            firstDate: _pickerFirstDate,
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) setSheet(() => date = picked);
                        },
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: kSheetActionHeight,
                    child: ElevatedButton(
                      onPressed: () async {
                        // Each of these used to bail out silently, so Save did
                        // nothing and said nothing.
                        String? problem =
                            validateAmountField(amountController.text);
                        if (problem == null &&
                            (fromId == null || toId == null)) {
                          problem = 'Pick both accounts';
                        } else if (problem == null && fromId == toId) {
                          problem = 'Pick two different accounts';
                        } else if (problem == null && crossCurrency()) {
                          problem =
                              validateAmountField(toAmountController.text);
                        }
                        if (problem != null) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(problem)));
                          return;
                        }
                        final amount =
                            parseMinor(amountController.text.trim())!;
                        final toAmount = crossCurrency()
                            ? parseMinor(toAmountController.text.trim())
                            : null;
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
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } finally {
      amountController.dispose();
      toAmountController.dispose();
      noteController.dispose();
    }
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
        text: _minAmount == null ? '' : minorToEditString(_minAmount!));
    final maxController = TextEditingController(
        text: _maxAmount == null ? '' : minorToEditString(_maxAmount!));
    DateTimeRange? range = _dateRange;

    // The sheet owns these controllers for its lifetime; dispose them once
    // it closes rather than leaking one set per open/close cycle.
    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) => StatefulBuilder(
          builder: (context, setSheet) => Padding(
            padding: bottomSheetPadding(context),
            // Scrollable so the filter list can still be reached (and Apply
            // tapped) when the keyboard shrinks the available height.
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Filters',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue:
                        categories.contains(category) ? category : null,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      DropdownMenuItem<String?>(
                          value: null, child: const Text('Any')),
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
                        DropdownMenuItem<int?>(
                            value: null, child: const Text('Any')),
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
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration:
                              const InputDecoration(labelText: 'Min amount'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: maxController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
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
                            firstDate: _pickerFirstDate,
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
                      SizedBox(
                        height: kSheetActionHeight,
                        child: ElevatedButton(
                          onPressed: () {
                            final appliedRange = range;
                            setState(() {
                              _categoryFilter = category;
                              _accountFilter = accountId;
                              _minAmount =
                                  parseMinor(minController.text.trim());
                              _maxAmount =
                                  parseMinor(maxController.text.trim());
                              _dateRange = appliedRange;
                            });
                            // A custom range can span years the provider hasn't
                            // loaded yet; load them so the filter shows everything.
                            if (appliedRange != null) {
                              context
                                  .read<ExpenseProvider>()
                                  .ensureYearsLoaded([
                                for (var y = appliedRange.start.year;
                                    y <= appliedRange.end.year;
                                    y++)
                                  y
                              ]);
                            }
                            Navigator.pop(context);
                          },
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } finally {
      minController.dispose();
      maxController.dispose();
    }
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
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<ExpenseProvider>();
    final filtered = _applyFilters(provider.expenses);
    if (filtered.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: const Text('Nothing to download for this filter.')),
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
    final currentYear = DateTime.now().year;
    // Every year from the earliest transaction to now, newest first, so old
    // data stays reachable (the list used to stop at 10 years back).
    final firstYear = _earliestYear < currentYear ? _earliestYear : currentYear;
    final years = [
      for (var y = currentYear; y >= firstYear; y--) y,
    ];

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
              decoration: InputDecoration(
                labelText: 'Search Expenses',
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
                onChanged: (y) {
                  if (y != null) _selectYear(y);
                },
              ),
              const SizedBox(width: 16),
              const Text('Month:'),
              const SizedBox(width: 8),
              DropdownButton<int?>(
                value: _selectedMonth,
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: const Text('All'),
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
                      onSelected: (_) => setState(() => _typeFilter = entry.$1),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Consumer<ExpenseProvider>(
              builder: (context, provider, _) {
                final expenses = _applyFilters(provider.expenses);
                // Distinguish "still loading" from "nothing here" — otherwise
                // a cold start shows "No expenses found." for a few frames,
                // which reads as data loss.
                if (expenses.isEmpty && provider.isLoading) {
                  return const ListSkeleton();
                }
                if (expenses.isEmpty) {
                  // Wrapped in a scrollable so pull-to-refresh still works from
                  // the empty state.
                  return RefreshIndicator(
                    onRefresh: () =>
                        context.read<ExpenseProvider>().reloadLoadedYears(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 80),
                        EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No transactions found',
                          message:
                              'Try a different period or clear your filters.',
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () =>
                      context.read<ExpenseProvider>().reloadLoadedYears(),
                  child: ListView.separated(
                    itemCount: expenses.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: scrollPadding(context, all: 12, fab: true),
                    itemBuilder: (context, index) {
                    final expense = expenses[index];
                    // Swiping is the only way to delete here, and a
                    // Dismissible exposes no action to TalkBack or switch
                    // access — so those users could not delete a transaction
                    // at all. Publish a custom semantics action and a
                    // long-press, matching the explicit delete buttons the
                    // budgets/accounts/recurring screens already have.
                    return Semantics(
                        customSemanticsActions: {
                          const CustomSemanticsAction(label: 'Delete'): () =>
                              _confirmDelete(expense),
                        },
                        child: Dismissible(
                          key: ValueKey(
                              expense.id ?? '${expense.description}-$index'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            color: Colors.red.shade400,
                            child:
                                const Icon(Icons.delete, color: Colors.white),
                          ),
                          confirmDismiss: (_) => _confirmDelete(expense),
                          child: Card(
                            margin: EdgeInsets.zero,
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
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  '${expense.category} · ${formatDateWithDay(expense.date)}'),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                      expense.isIncome
                                          ? '+${_rowAmount(context, expense)}'
                                          : expense.isTransfer
                                              ? _rowAmount(context, expense)
                                              : '-${_rowAmount(context, expense)}',
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
                                              ? 'Income'
                                              : 'Transfer',
                                      style: TextStyle(
                                          color: mutedTextColor(context),
                                          fontSize: 12)),
                                ],
                              ),
                              onTap: () => expense.isTransfer
                                  ? _editTransfer(expense)
                                  : _editExpense(expense),
                              onLongPress: () => _confirmDelete(expense),
                            ),
                          ),
                        ));
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
