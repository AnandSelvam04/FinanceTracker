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
import '../utils/category_icons.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/db_constants.dart';
import '../utils/insets.dart';
import '../utils/transaction_filter.dart';
import '../widgets/category_avatar.dart';
import '../widgets/empty_state.dart';
import '../widgets/fade_slide_in.dart';
import '../widgets/skeleton.dart';
import '../widgets/swipe_delete_background.dart';
import '../widgets/transaction_edit_sheet.dart';
import '../widgets/dispose_with_route.dart';

class ExpenseListScreen extends StatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  State<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends State<ExpenseListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _selectedYear = DateTime.now().year;
  int? _selectedMonth = DateTime.now().month;
  String? _typeFilter;

  /// Rows already given their entrance animation, keyed by transaction id.
  /// Recycled `ListView` rows rebuild on scroll, so this guards against the
  /// fade-in replaying every time a row scrolls back into view.
  final Set<Object> _animatedRows = {};

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Human label for the current period chip, e.g. "2026 · August" or
  /// "2026 · All months".
  String get _periodLabel =>
      '$_selectedYear · ${_selectedMonth == null ? 'All months' : monthName(_selectedMonth!)}';

  /// Compact period picker (year + month) opened from the toolbar chip, so the
  /// two bare dropdowns no longer sit permanently across the top of the list.
  Future<void> _showPeriodPicker() async {
    final currentYear = DateTime.now().year;
    final firstYear = _earliestYear < currentYear ? _earliestYear : currentYear;
    final years = [for (var y = currentYear; y >= firstYear; y--) y];
    await showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: bottomSheetPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Period', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _selectedYear,
                      decoration: const InputDecoration(labelText: 'Year'),
                      items: years
                          .map((y) => DropdownMenuItem(
                              value: y, child: Text(y.toString())))
                          .toList(),
                      onChanged: (y) {
                        if (y == null) return;
                        setSheet(() => _selectedYear = y);
                        _selectYear(y);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      initialValue: _selectedMonth,
                      decoration: const InputDecoration(labelText: 'Month'),
                      items: [
                        DropdownMenuItem<int?>(
                            value: null, child: const Text('All months')),
                        ...List.generate(
                            12,
                            (i) => DropdownMenuItem<int?>(
                                value: i + 1, child: Text(monthName(i + 1)))),
                      ],
                      onChanged: (m) {
                        setSheet(() => _selectedMonth = m);
                        setState(() => _selectedMonth = m);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
        title: const Text('Delete transaction?'),
        content: Text('Remove "${expense.description}" for '
            '${_rowAmount(context, expense)}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
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

    // DisposeWithRoute disposes the controllers once the sheet has closed.
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DisposeWithRoute(
        notifiers: [minController, maxController],
        child: StatefulBuilder(
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
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 12),
                  if (accounts.isNotEmpty) ...[
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
                    const SizedBox(height: 12),
                  ],
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
                        child: FilledButton(
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
      ),
    );
  }

  String _fmtRange(DateTimeRange r) =>
      '${formatShortDate(r.start)} → ${formatShortDate(r.end)}';

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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search transactions',
                prefixIcon: const Icon(Icons.search),
                // A clear button so a stale query doesn't hide everything with
                // no obvious way to reset it.
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
          // One compact toolbar row: the period opens a picker, and the type
          // chips sit beside it — instead of two bare dropdowns plus a
          // separate chip strip stacked down the screen.
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                ActionChip(
                  avatar: const Icon(Icons.calendar_month, size: 18),
                  label: Text(_periodLabel),
                  onPressed: _showPeriodPicker,
                ),
                const SizedBox(width: 8),
                const _ToolbarDivider(),
                const SizedBox(width: 8),
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
                // The filter icon in the app bar was the only sign that
                // category/account/amount filters were narrowing the list.
                // Surface them here, with a one-tap clear.
                if (_hasAdvancedFilters)
                  InputChip(
                    avatar: const Icon(Icons.filter_alt, size: 18),
                    label: const Text('Filters on'),
                    selected: true,
                    onPressed: _openFilterSheet,
                    onDeleted: () => setState(() {
                      _categoryFilter = null;
                      _accountFilter = null;
                      _minAmount = null;
                      _maxAmount = null;
                      _dateRange = null;
                    }),
                    deleteButtonTooltipMessage: 'Clear filters',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
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
                // Flatten into day headers followed by that day's rows (the
                // list is already newest-first), so the date is said once per
                // day instead of repeated on every row.
                final items = <Object>[];
                final daySpent = <DateTime, int>{};
                DateTime? day;
                for (final e in expenses) {
                  final d = DateUtils.dateOnly(e.date);
                  if (d != day) {
                    day = d;
                    items.add(d);
                  }
                  items.add(e);
                  if (e.isExpense) {
                    daySpent[d] = (daySpent[d] ?? 0) + provider.baseAmountOf(e);
                  }
                }
                final spent = expenses
                    .where((e) => e.isExpense)
                    .fold<int>(0, (s, e) => s + provider.baseAmountOf(e));
                final income = expenses
                    .where((e) => e.isIncome)
                    .fold<int>(0, (s, e) => s + provider.baseAmountOf(e));
                return RefreshIndicator(
                  onRefresh: () =>
                      context.read<ExpenseProvider>().reloadLoadedYears(),
                  child: ListView.builder(
                    // +1 for the period summary leading the list.
                    itemCount: items.length + 1,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: scrollPadding(context, all: 12, top: 4, fab: true),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _PeriodSummary(
                          count: expenses.length,
                          spent: spent,
                          income: income,
                        );
                      }
                      final item = items[index - 1];
                      if (item is DateTime) {
                        return _DayHeader(
                            day: item, spent: daySpent[item] ?? 0);
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildRow(context, item as Expense, index),
                      );
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

  Widget _buildRow(BuildContext context, Expense expense, int index) {
    final rowKey = expense.id ?? '${expense.description}-$index';
    // Set.add returns true only the first time this row is built, so each row
    // fades in once and does not replay when it scrolls back into view.
    final firstAppearance = _animatedRows.add(rowKey);
    final amountColor = expense.isIncome
        ? incomeColor(context)
        : expense.isTransfer
            ? transferColor(context)
            : expenseColor(context);
    final amount = expense.isIncome
        ? '+${_rowAmount(context, expense)}'
        : expense.isTransfer
            ? _rowAmount(context, expense)
            : '-${_rowAmount(context, expense)}';
    final detail = expense.isTransfer
        ? 'Transfer'
        : expense.isIncome
            ? '${expense.category} · Income'
            : '${expense.category} · ${expense.paymentMode}';
    // Swiping is the only way to delete here, and a Dismissible exposes no
    // action to TalkBack or switch access — so those users could not delete a
    // transaction at all. Publish a custom semantics action and a long-press,
    // matching the explicit delete buttons the budgets/accounts/recurring
    // screens already have.
    final Widget row = Semantics(
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Delete'): () =>
              _confirmDelete(expense),
        },
        child: Dismissible(
          key: ValueKey(rowKey),
          direction: DismissDirection.endToStart,
          background: const SwipeDeleteBackground(),
          confirmDismiss: (_) => _confirmDelete(expense),
          child: Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: _CategoryAvatar(expense: expense),
              title: Text(
                  expense.description.isEmpty
                      ? '(no description)'
                      : expense.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle:
                  Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text(amount,
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: amountColor)),
              onTap: () => editTransactionSheet(context, expense,
                  firstDate: _pickerFirstDate),
              onLongPress: () => _confirmDelete(expense),
            ),
          ),
        ));
    return firstAppearance ? FadeSlideIn(child: row) : row;
  }
}

/// Totals for whatever the current filters show, leading the list so the
/// period's spend is visible without leaving the Transactions tab.
class _PeriodSummary extends StatelessWidget {
  final int count;
  final int spent;
  final int income;

  const _PeriodSummary({
    required this.count,
    required this.spent,
    required this.income,
  });

  @override
  Widget build(BuildContext context) {
    final muted = mutedTextColor(context);
    Widget figure(String label, int amount, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600,
                      color: muted)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(formatMoney(amount),
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ),
            ],
          ),
        );
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            figure('Spent', spent, expenseColor(context)),
            figure('Income', income, incomeColor(context)),
            Text('$count ${count == 1 ? 'entry' : 'entries'}',
                style: TextStyle(fontSize: 12, color: muted)),
          ],
        ),
      ),
    );
  }
}

/// Date heading over one day's transactions, with that day's spend.
class _DayHeader extends StatelessWidget {
  final DateTime day;
  final int spent;

  const _DayHeader({required this.day, required this.spent});

  String _label() {
    final today = DateUtils.dateOnly(DateTime.now());
    if (day == today) return 'Today';
    // Calendar arithmetic, not a 24h Duration, so a DST change doesn't lose
    // the "Yesterday" label for a day.
    if (day == DateTime(today.year, today.month, today.day - 1)) {
      return 'Yesterday';
    }
    return formatDateWithDay(day);
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: mutedTextColor(context),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          Expanded(child: Text(_label(), style: style)),
          if (spent > 0) Text('-${formatMoney(spent)}', style: style),
        ],
      ),
    );
  }
}

/// Leading avatar for a transaction row: a category icon on the category's
/// colour for spends, keeping the green/blue-grey semantics for income and
/// transfers.
class _CategoryAvatar extends StatelessWidget {
  final Expense expense;
  const _CategoryAvatar({required this.expense});

  @override
  Widget build(BuildContext context) {
    if (expense.isTransfer) {
      return CircleAvatar(
        backgroundColor: transferAvatarColor(context),
        child: Icon(Icons.swap_horiz, color: transferColor(context)),
      );
    }
    if (expense.isIncome) {
      return CircleAvatar(
        backgroundColor: incomeAvatarColor(context),
        child:
            Icon(categoryIcon(expense.category), color: incomeColor(context)),
      );
    }
    return CategoryAvatar(category: expense.category);
  }
}

/// A short vertical rule separating the period chip from the type chips in the
/// transactions toolbar.
class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 1,
        height: 24,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}
