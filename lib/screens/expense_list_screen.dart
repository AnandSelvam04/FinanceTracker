import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/account.dart';
import '../models/expense.dart';
import '../models/investment.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/investment_provider.dart';
import '../services/backup_service.dart';
import '../services/db_service.dart';
import '../services/excel_export.dart';
import '../utils/haptics.dart';
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
import 'investment_type_screen.dart';
import '../utils/font_sizes.dart';
import '../utils/dimens.dart';

part 'expense_list/filter_sheet.dart';
part 'expense_list/list_widgets.dart';

class ExpenseListScreen extends StatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  State<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends State<ExpenseListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  /// The year shown, or null for every year (to search the whole history).
  int? _selectedYear = DateTime.now().year;
  int? _selectedMonth = DateTime.now().month;
  String? _typeFilter;

  /// Ids of the rows picked for a bulk action. Non-empty means the screen is
  /// in selection mode (entered by long-pressing a row).
  final Set<int> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  /// Ids of the transactions the list currently shows, for Select all.
  List<int> _visibleIds = const [];

  /// Largest first instead of newest first — to find the big spends.
  bool _sortByAmount = false;

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

  /// Human label for the current period chip, e.g. "2026 · August",
  /// "2026 · All months" or "All years".
  String get _periodLabel {
    final month =
        _selectedMonth == null ? 'All months' : monthName(_selectedMonth!);
    if (_selectedYear == null) {
      return _selectedMonth == null ? 'All years' : 'All years · $month';
    }
    return '$_selectedYear · $month';
  }

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
              const SizedBox(height: Space.lg),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      initialValue: _selectedYear,
                      decoration: const InputDecoration(labelText: 'Year'),
                      items: [
                        // Every year at once, so a search reaches the whole
                        // history instead of one year of it.
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('All years')),
                        ...years.map((y) => DropdownMenuItem<int?>(
                            value: y, child: Text(y.toString()))),
                      ],
                      onChanged: (y) {
                        setSheet(() => _selectedYear = y);
                        _selectYear(y);
                      },
                    ),
                  ),
                  const SizedBox(width: Space.md),
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

  /// Loads the data needed to show [year], or every year when it is null
  /// (the provider only holds the years it has been asked for).
  Future<void> _selectYear(int? year) async {
    setState(() => _selectedYear = year);
    final provider = context.read<ExpenseProvider>();
    if (year != null) {
      await provider.ensureYearLoaded(year);
      return;
    }
    final currentYear = DateTime.now().year;
    // Asked afresh rather than read from _earliestYear, which is only as
    // old as the data was when this tab was first built.
    final bounds = await DBService().transactionYearBounds();
    final first = bounds?.$1 ?? _earliestYear;
    final last =
        bounds == null || bounds.$2 < currentYear ? currentYear : bounds.$2;
    if (mounted && first < _earliestYear) {
      setState(() => _earliestYear = first);
    }
    await provider.ensureYearsLoaded([for (var y = last; y >= first; y--) y]);
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
  ///
  /// A refund (stored negative) is formatted by its size, [Expense.amount]'s
  /// absolute value, since callers put the sign in front themselves.
  String _rowAmount(BuildContext context, Expense expense) {
    final account =
        context.read<AccountProvider>().accountById(expense.accountId);
    final amount = expense.amount.abs();
    return account == null
        ? formatMoney(amount)
        : formatMoneyIn(account.symbol, amount);
  }

  void _toggleSelected(Expense e) {
    final id = e.id;
    if (id == null) return;
    // Entering multi-select (the first pick) is the weightier moment.
    _selected.isEmpty ? Haptics.medium() : Haptics.tick();
    setState(() =>
        _selected.contains(id) ? _selected.remove(id) : _selected.add(id));
  }

  /// The selected rows that are still loaded (a row can vanish under the
  /// selection if it is edited into another period).
  List<Expense> get _selectedRows => [
        for (final e in context.read<ExpenseProvider>().expenses)
          if (e.id != null && _selected.contains(e.id)) e,
      ];

  /// The contextual app bar shown while rows are selected.
  AppBar _selectionBar() {
    final allSelected =
        _visibleIds.isNotEmpty && _visibleIds.every(_selected.contains);
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cancel selection',
        onPressed: () => setState(_selected.clear),
      ),
      title: Text('${_selected.length} selected'),
      actions: [
        IconButton(
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          tooltip: allSelected ? 'Select none' : 'Select all',
          onPressed: () => setState(() =>
              allSelected ? _selected.clear() : _selected.addAll(_visibleIds)),
        ),
        IconButton(
          icon: const Icon(Icons.category_outlined),
          tooltip: 'Change category',
          onPressed: _bulkRecategorize,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete selected',
          onPressed: _bulkDelete,
        ),
      ],
    );
  }

  Future<void> _bulkDelete() async {
    final rows = _selectedRows;
    if (rows.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final expenses = context.read<ExpenseProvider>();
    final accounts = context.read<AccountProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${rows.length} '
            '${rows.length == 1 ? 'transaction' : 'transactions'}?'),
        content: const Text('Account balances and totals update to match. '
            'You can undo straight after.'),
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
    if (ok != true) return;
    // Leave selection mode at once, not after the delete's reload.
    if (mounted) setState(_selected.clear);
    await expenses.deleteExpenses([for (final e in rows) e.id!]);
    await accounts.refreshBalances();
    messenger.showSnackBar(SnackBar(
      content: Text('Deleted ${rows.length} '
          '${rows.length == 1 ? 'transaction' : 'transactions'}'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          // Same ids, so anything referring to them still lines up.
          await expenses.addExpenses(rows);
          await accounts.refreshBalances();
        },
      ),
    ));
  }

  Future<void> _bulkRecategorize() async {
    final rows = _selectedRows;
    final movable = rows.where((e) => !e.isTransfer).toList();
    final messenger = ScaffoldMessenger.of(context);
    if (movable.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Transfers have no category to change.')));
      return;
    }
    final expenses = context.read<ExpenseProvider>();
    final existing = {
      for (final e in expenses.expenses)
        if (!e.isTransfer && e.category.trim().isNotEmpty) e.category.trim(),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final category = await showDialog<String>(
      context: context,
      builder: (_) =>
          _CategoryPickerDialog(count: movable.length, suggestions: existing),
    );
    if (category == null || category.trim().isEmpty) return;
    final before = [for (final e in movable) (e.id!, e.category)];
    if (mounted) setState(_selected.clear);
    await expenses.setCategory([for (final e in movable) e.id!], category);
    final skipped = rows.length - movable.length;
    messenger.showSnackBar(SnackBar(
      content: Text('Moved ${movable.length} to $category'
          '${skipped > 0 ? ' ($skipped transfer${skipped == 1 ? '' : 's'} skipped)' : ''}'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          // Grouped by old category: one write (and one reload) per group,
          // not per row.
          final byOld = <String, List<int>>{};
          for (final (id, old) in before) {
            byOld.putIfAbsent(old, () => []).add(id);
          }
          for (final MapEntry(key: old, value: ids) in byOld.entries) {
            await expenses.setCategory(ids, old);
          }
        },
      ),
    ));
  }

  Future<bool> _confirmDelete(Expense expense) async {
    Haptics.medium();
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
  List<Expense> _applyFilters(List<Expense> all) => _filter.apply(all);

  TransactionFilter get _filter => TransactionFilter(
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
        accountNames: {
          for (final a in context.read<AccountProvider>().accounts)
            a.id!: a.name,
        },
      );

  Future<void> _openFilterSheet() async {
    final provider = context.read<ExpenseProvider>();
    final accounts = context.read<AccountProvider>().accounts;
    final categories = provider.expenses
        .map((e) => e.category)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    // Null when the sheet is dismissed: the filters stay as they were.
    final picked = await showModalBottomSheet<_AdvancedFilters>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(
        categories: categories,
        accounts: accounts,
        firstDate: _pickerFirstDate,
        initial: (
          category: _categoryFilter,
          accountId: _accountFilter,
          minAmount: _minAmount,
          maxAmount: _maxAmount,
          range: _dateRange,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _categoryFilter = picked.category;
      _accountFilter = picked.accountId;
      _minAmount = picked.minAmount;
      _maxAmount = picked.maxAmount;
      _dateRange = picked.range;
    });
    // A custom range can span years the provider hasn't loaded yet; load
    // them so the filter shows everything.
    final range = picked.range;
    if (range != null) {
      provider.ensureYearsLoaded(
          [for (var y = range.start.year; y <= range.end.year; y++) y]);
    }
  }

  String get _filterLabel {
    final year = _selectedYear == null ? 'all-years' : '$_selectedYear';
    return _selectedMonth == null
        ? year
        : '$year-${_selectedMonth.toString().padLeft(2, '0')}';
  }

  /// Downloads exactly what the current filters show, via the share sheet:
  /// as a CSV file, or with [excel] as a workbook with a summary, the
  /// transactions and spending by category.
  Future<void> _downloadFiltered({required bool excel}) async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<ExpenseProvider>();
    final accounts = context.read<AccountProvider>().accounts;
    final filtered = _applyFilters(provider.expenses);
    if (filtered.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: const Text('Nothing to download for this filter.')),
      );
      return;
    }
    try {
      final file = excel
          ? await ExcelExport.write(
              ExcelExport.reportSheets(
                periodLabel: 'Transactions ($_filterLabel)',
                transactions: filtered,
                baseAmountOf: provider.baseAmountOf,
                accountNames: {
                  for (final a in accounts)
                    if (a.id != null) a.id!: a.name,
                },
              ),
              name: 'expenses_$_filterLabel',
            )
          : await writeExpensesCsvFile(
              filtered,
              filename: 'expenses_$_filterLabel.csv',
            );
      await Share.shareXFiles(
        [XFile(file.path, mimeType: excel ? ExcelExport.mimeType : 'text/csv')],
        subject: 'Finance Tracker — Transactions ($_filterLabel)',
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back leaves selection mode before it leaves the screen.
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: _selecting
            ? _selectionBar()
            : AppBar(
                title: const Text('Transactions'),
                actions: [
                  // Newest first (grouped by day) or largest first, to find
                  // the big spends.
                  IconButton(
                    icon:
                        Icon(_sortByAmount ? Icons.trending_down : Icons.sort),
                    tooltip: _sortByAmount
                        ? 'Sorted: largest first'
                        : 'Sorted: newest first',
                    onPressed: () =>
                        setState(() => _sortByAmount = !_sortByAmount),
                  ),
                  IconButton(
                    icon: Icon(_hasAdvancedFilters
                        ? Icons.filter_alt
                        : Icons.filter_alt_outlined),
                    tooltip: 'Filters',
                    onPressed: _openFilterSheet,
                  ),
                  PopupMenuButton<bool>(
                    icon: const Icon(Icons.download),
                    tooltip: 'Download what is shown',
                    onSelected: (excel) => _downloadFiltered(excel: excel),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: false, child: Text('As CSV')),
                      PopupMenuItem(value: true, child: Text('As Excel')),
                    ],
                  ),
                ],
              ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.md, Space.sm, Space.md, Space.xs),
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
                padding: const EdgeInsets.symmetric(horizontal: Space.md),
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.calendar_month, size: 18),
                    label: Text(_periodLabel),
                    onPressed: _showPeriodPicker,
                  ),
                  const SizedBox(width: Space.sm),
                  const _ToolbarDivider(),
                  const SizedBox(width: Space.sm),
                  for (final entry in [
                    (null, 'All'),
                    (DbConstants.txExpense, 'Expenses'),
                    (DbConstants.txIncome, 'Income'),
                    (DbConstants.txTransfer, 'Transfers'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: Space.sm),
                      child: ChoiceChip(
                        label: Text(entry.$2),
                        selected: _typeFilter == entry.$1,
                        onSelected: (_) =>
                            setState(() => _typeFilter = entry.$1),
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
            const SizedBox(height: Space.xs),
            Expanded(
              child: Consumer2<ExpenseProvider, InvestmentProvider>(
                builder: (context, provider, investmentProvider, _) {
                  final expenses = _applyFilters(provider.expenses);
                  // With an account chosen, the investments paid from it too:
                  // they move its balance, so the list must show them to add up.
                  final investments =
                      _filter.investmentsFor(investmentProvider.investments);
                  // Distinguish "still loading" from "nothing here" — otherwise
                  // a cold start shows "No expenses found." for a few frames,
                  // which reads as data loss.
                  if (expenses.isEmpty && provider.isLoading) {
                    return const ListSkeleton();
                  }
                  if (expenses.isEmpty && investments.isEmpty) {
                    // Wrapped in a scrollable so pull-to-refresh still works from
                    // the empty state.
                    return RefreshIndicator(
                      onRefresh: () =>
                          context.read<ExpenseProvider>().reloadLoadedYears(),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 80),
                          // A search that finds nothing in the year on show
                          // is one tap from looking through all of them.
                          if (_selectedYear != null &&
                              _dateRange == null &&
                              _searchQuery.trim().isNotEmpty)
                            EmptyState(
                              icon: Icons.receipt_long_outlined,
                              title: 'No transactions found',
                              message: 'Nothing matches in '
                                  '${_periodLabel.replaceAll(' · ', ', ')}.',
                              actionLabel: 'Search all years',
                              onAction: () {
                                setState(() => _selectedMonth = null);
                                _selectYear(null);
                              },
                            )
                          else
                            const EmptyState(
                              icon: Icons.receipt_long_outlined,
                              title: 'No transactions found',
                              message: 'Try a different period or clear your '
                                  'filters.',
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
                  // Both lists are newest-first; merge them by date.
                  int size(Object row) => row is Investment
                      ? row.amount.abs()
                      : provider.baseAmountOf(row as Expense).abs();
                  final rows = <Object>[...expenses, ...investments]..sort(
                      (a, b) => _sortByAmount
                          ? size(b).compareTo(size(a))
                          : _dateOf(b).compareTo(_dateOf(a)));
                  _visibleIds = [
                    for (final e in expenses)
                      if (e.id != null) e.id!,
                  ];
                  for (final row in rows) {
                    final d = DateUtils.dateOnly(_dateOf(row));
                    // Day headers only make sense in date order; sorted by
                    // amount, each row carries its own date instead.
                    if (!_sortByAmount && d != day) {
                      day = d;
                      items.add(d);
                    }
                    items.add(row);
                    if (row is Expense && row.isExpense) {
                      daySpent[d] =
                          (daySpent[d] ?? 0) + provider.baseAmountOf(row);
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
                      padding: scrollPadding(context, all: Space.md, top: Space.xs),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _PeriodSummary(
                            count: expenses.length + investments.length,
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
                          padding: const EdgeInsets.only(bottom: Space.sm),
                          child: item is Investment
                              ? _InvestmentRow(investment: item)
                              : _buildRow(context, item as Expense, index),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static DateTime _dateOf(Object row) =>
      row is Investment ? row.date : (row as Expense).date;

  Widget _buildRow(BuildContext context, Expense expense, int index) {
    final rowKey = expense.id ?? '${expense.description}-$index';
    // Set.add returns true only the first time this row is built, so each row
    // fades in once and does not replay when it scrolls back into view.
    final firstAppearance = _animatedRows.add(rowKey);
    final amountColor = expense.isIncome || expense.isRefund
        ? incomeColor(context)
        : expense.isTransfer
            ? transferColor(context)
            : expenseColor(context);
    // A refund is stored negative; show it as money back, not "-₹-500".
    final amount = expense.isRefund
        ? '+${_rowAmount(context, expense)}'
        : expense.isIncome
            ? '+${_rowAmount(context, expense)}'
            : expense.isTransfer
                ? _rowAmount(context, expense)
                : '-${_rowAmount(context, expense)}';
    final detail = expense.isTransfer
        ? 'Transfer'
        : expense.isRefund
            ? '${expense.category} · Refund'
            : expense.isIncome
                ? '${expense.category} · Income'
                : '${expense.category} · ${expense.paymentMode}';
    final detailLine =
        _sortByAmount ? '${formatShortDate(expense.date)} · $detail' : detail;
    final selected = expense.id != null && _selected.contains(expense.id);
    // Swiping is the only way to delete here, and a Dismissible exposes no
    // action to TalkBack or switch access — so those users could not delete a
    // transaction at all. Publish a custom semantics action and a long-press,
    // matching the explicit delete buttons the budgets/accounts/recurring
    // screens already have.
    final Widget row = Semantics(
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Delete'): () =>
              _confirmDelete(expense),
          if (expense.id != null)
            CustomSemanticsAction(label: selected ? 'Deselect' : 'Select'):
                () => _toggleSelected(expense),
        },
        child: Dismissible(
          key: ValueKey(rowKey),
          // No swipe-to-delete while picking rows for a bulk action.
          direction:
              _selecting ? DismissDirection.none : DismissDirection.endToStart,
          background: const SwipeDeleteBackground(),
          confirmDismiss: (_) => _confirmDelete(expense),
          child: Card(
            margin: EdgeInsets.zero,
            color: selected
                ? Theme.of(context).colorScheme.secondaryContainer
                : null,
            child: ListTile(
              leading: _selecting
                  ? CircleAvatar(
                      backgroundColor: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                      child: Icon(selected ? Icons.check : null,
                          color: Theme.of(context).colorScheme.onPrimary),
                    )
                  : _CategoryAvatar(expense: expense),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                        expense.description.isEmpty
                            ? '(no description)'
                            : expense.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  // A receipt photo is kept with this row.
                  if (expense.attachment != null)
                    Padding(
                      padding: const EdgeInsets.only(left: Space.xs),
                      child: Icon(Icons.attach_file,
                          size: 15,
                          semanticLabel: 'Has a receipt photo',
                          color: mutedTextColor(context)),
                    ),
                ],
              ),
              // A note, when there is one, gets its own line under the
              // category so it is readable without opening the row.
              subtitle: Text(
                  expense.noteText == null
                      ? detailLine
                      : '$detailLine\n${expense.noteText}',
                  maxLines: expense.noteText == null ? 1 : 2,
                  overflow: TextOverflow.ellipsis),
              trailing: Text(amount,
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: amountColor)),
              // Edit, Duplicate or Delete — duplicating used to need the
              // edit sheet opened first.
              onTap: _selecting
                  ? () => _toggleSelected(expense)
                  : () => transactionRowActions(context, expense,
                      firstDate: _pickerFirstDate,
                      onDelete: () => _confirmDelete(expense)),
              // Long-press starts picking rows for a bulk action; deleting a
              // single row is in its tap menu and on swipe.
              onLongPress: () => _toggleSelected(expense),
            ),
          ),
        ));
    return firstAppearance ? FadeSlideIn(child: row) : row;
  }
}
