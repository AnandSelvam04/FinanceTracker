import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/investment.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/investment_provider.dart';
import '../services/category_memory.dart';
import '../services/db_service.dart';
import '../services/sms_service.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/insets.dart';

/// The dropdown/segmented value that stands for "let me type my own", shared by
/// the category box and the investment-type box.
const String _kOther = 'Other';

/// Review queue for transactions found in bank SMS alerts.
///
/// Nothing is posted without an explicit Import: the parser matches templates
/// banks change without notice, so a bad match must cost a tap rather than a
/// wrong balance. Dismissed messages are remembered (see
/// [DBService.ignoreSourceRefs]) so a later scan does not offer them again —
/// unless the user turns on "Show dismissed" to recover one.
class SmsReviewScreen extends StatefulWidget {
  const SmsReviewScreen({super.key});

  @override
  State<SmsReviewScreen> createState() => _SmsReviewScreenState();
}

/// The preset spans offered before falling back to a custom date range.
enum _ScanSpan { twoDays, week, month, custom }

class _SmsReviewScreenState extends State<SmsReviewScreen> {
  static const _expenseCategories = [
    'Food', 'Transport', 'Shopping', 'Bills', //
    'Entertainment', 'Health', 'Education', _kOther,
  ];
  static const _incomeCategories = [
    'Salary', 'Business', 'Interest', 'Dividends', 'Gift', 'Refund', _kOther,
  ];

  List<SmsDraft> _drafts = [];
  bool _loading = true;
  bool _importing = false;

  /// Null until a scan has run; set when the permission was refused, so the
  /// empty state can explain itself rather than claiming nothing was found.
  bool _permissionDenied = false;

  /// Which span the next scan covers. [_customRange] carries the dates when
  /// this is [_ScanSpan.custom].
  _ScanSpan _span = _ScanSpan.twoDays;
  DateTimeRange? _customRange;

  /// Whether the scan also surfaces messages the user dismissed before, so a
  /// wrongly dismissed one can be pulled back in and imported.
  bool _includeDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  /// Built-in investment types plus any the user already uses, "Other" last —
  /// the same list the Add Investment screen offers.
  List<String> get _investmentTypes {
    final base =
        Investment.builtInTypes.where((t) => t != _kOther).toList();
    for (final t in context.read<InvestmentProvider>().usedTypes()) {
      if (t.isNotEmpty && !base.contains(t)) base.add(t);
    }
    base.add(_kOther);
    return base;
  }

  /// The lower/upper bounds the current span scans, and a caption for it. The
  /// upper bound is null for the presets (they run up to now).
  ({DateTime? from, DateTime? to, Duration window, String label}) get _range {
    switch (_span) {
      case _ScanSpan.twoDays:
        return (
          from: null,
          to: null,
          window: const Duration(days: 2),
          label: 'the last 2 days'
        );
      case _ScanSpan.week:
        return (
          from: null,
          to: null,
          window: const Duration(days: 7),
          label: 'the last 7 days'
        );
      case _ScanSpan.month:
        return (
          from: null,
          to: null,
          window: const Duration(days: 30),
          label: 'the last 30 days'
        );
      case _ScanSpan.custom:
        final r = _customRange!;
        // Include the whole of the end day, not just its first instant.
        final to = DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59);
        return (
          from: DateTime(r.start.year, r.start.month, r.start.day),
          to: to,
          window: SmsService.defaultWindow,
          label: '${formatIsoDate(r.start)} – ${formatIsoDate(r.end)}'
        );
    }
  }

  Future<void> _scan() async {
    setState(() => _loading = true);
    final accountProvider = context.read<AccountProvider>();
    if (accountProvider.accounts.isEmpty) {
      await accountProvider.fetchAccounts();
    }

    final granted = await SmsService.requestPermission();
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _loading = false;
        _permissionDenied = true;
        _drafts = [];
      });
      return;
    }

    final range = _range;
    final found = await SmsService.scan(
      window: range.window,
      from: range.from,
      to: range.to,
      includeDismissed: _includeDismissed,
    );
    // Hand-entered rows near the scan window, so a message that duplicates one
    // can be flagged rather than silently recorded twice. Bounded to the
    // window the candidates can fall in (plus the duplicate tolerance either
    // side) rather than reading a ledger that grows without limit.
    final now = DateTime.now();
    final lower = range.from ?? now.subtract(range.window);
    final upper = range.to ?? now;
    final existing = await DBService().getExpensesByDateRange(
      lower.subtract(const Duration(days: 7)),
      upper.add(const Duration(days: 7)),
    );
    // What each merchant was filed under before, so a familiar one arrives
    // with its category already set.
    final memory =
        CategoryMemory.fromRows(await DBService().merchantCategoryCounts());
    if (!mounted) return;
    setState(() {
      _permissionDenied = false;
      _drafts = [
        for (final p in found)
          SmsDraft.from(p, accountProvider.accounts,
              existing: existing, memory: memory)
      ];
      _loading = false;
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(
              start: now.subtract(const Duration(days: 7)), end: now),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _span = _ScanSpan.custom;
      _customRange = picked;
    });
    await _scan();
  }

  void _selectSpan(_ScanSpan span) {
    if (span == _ScanSpan.custom) {
      _pickCustomRange();
      return;
    }
    setState(() => _span = span);
    _scan();
  }

  List<SmsDraft> get _selected =>
      _drafts.where((d) => d.selected).toList(growable: false);

  Future<void> _importSelected() async {
    final chosen = _selected;
    if (chosen.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);

    // A transfer with no destination would debit the source and credit
    // nothing, quietly losing the money rather than moving it.
    final incomplete = chosen.where((d) => d.needsDestination).length;
    if (incomplete > 0) {
      messenger.showSnackBar(SnackBar(
        content: Text('$incomplete transfer'
            '${incomplete == 1 ? ' needs a' : 's need'} destination account.'),
      ));
      return;
    }

    final expenseProvider = context.read<ExpenseProvider>();
    final accountProvider = context.read<AccountProvider>();
    final investmentProvider = context.read<InvestmentProvider>();

    final investmentDrafts =
        chosen.where((d) => d.asInvestment).toList(growable: false);
    final txDrafts =
        chosen.where((d) => !d.asInvestment).toList(growable: false);

    setState(() => _importing = true);
    try {
      // One transaction, matching the CSV importer: a failure part-way through
      // leaves nothing half-imported.
      if (txDrafts.isNotEmpty) {
        await DBService().insertExpenses([for (final d in txDrafts) d.toExpense()]);
      }
      // The investments table carries no sourceRef, so a contribution imported
      // from a message can't be deduped by the sourceRef check — mark its ref
      // as seen instead, so a rescan does not offer it again.
      for (final d in investmentDrafts) {
        await investmentProvider.addInvestment(d.toInvestment());
      }
      // A collapsed pair posts one row but consumes two messages; the absorbed
      // one has to be marked seen or the next scan offers it on its own. An
      // investment draft marks its own ref too, for the reason above.
      await DBService().ignoreSourceRefs([
        for (final d in chosen) ...d.parsed.alsoCoversRefs,
        for (final d in investmentDrafts) d.parsed.sourceRef,
      ]);
      // Importing a message the user had dismissed clears that rejection, so
      // the dismissal list doesn't keep a now-imported message in it. Only for
      // rows that land in the expenses table with their own sourceRef —
      // investment refs must stay on the list, since that is what keeps a
      // rescan from re-offering them.
      await DBService()
          .unignoreSourceRefs([for (final d in txDrafts) d.parsed.sourceRef]);
      await expenseProvider.reloadLoadedYears();
      await accountProvider.refreshBalances();
      if (!mounted) return;
      setState(() => _drafts.removeWhere((d) => d.selected));
      messenger.showSnackBar(
        SnackBar(content: Text('Imported ${chosen.length} transaction'
            '${chosen.length == 1 ? '' : 's'}.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _dismiss(SmsDraft draft) async {
    setState(() => _drafts.remove(draft));
    await DBService().ignoreSourceRefs([draft.parsed.sourceRef]);
  }

  Future<void> _showRawMessage(SmsDraft draft) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(draft.parsed.sender),
        content: SingleChildScrollView(child: Text(draft.parsed.body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selected.length;
    final busy = _loading || _importing;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import from SMS'),
        actions: [
          PopupMenuButton<_ScanSpan>(
            icon: const Icon(Icons.date_range),
            tooltip: 'Scan range',
            enabled: !busy,
            onSelected: _selectSpan,
            itemBuilder: (context) => [
              _spanItem(_ScanSpan.twoDays, 'Last 2 days'),
              _spanItem(_ScanSpan.week, 'Last 7 days'),
              _spanItem(_ScanSpan.month, 'Last 30 days'),
              _spanItem(_ScanSpan.custom, 'Custom range…'),
            ],
          ),
          IconButton(
            icon: Icon(_includeDismissed
                ? Icons.visibility
                : Icons.visibility_off_outlined),
            tooltip: _includeDismissed
                ? 'Hiding nothing — dismissed messages shown'
                : 'Show dismissed messages',
            onPressed: busy
                ? null
                : () {
                    setState(() => _includeDismissed = !_includeDismissed);
                    _scan();
                  },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rescan inbox',
            onPressed: busy ? null : _scan,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _drafts.isEmpty
              ? _EmptyState(
                  permissionDenied: _permissionDenied,
                  rangeLabel: _range.label,
                  includeDismissed: _includeDismissed,
                  onRetry: _scan)
              : Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        itemCount: _drafts.length,
                        padding: scrollPadding(context, all: 12),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _DraftCard(
                          key: ValueKey(_drafts[i].parsed.sourceRef),
                          draft: _drafts[i],
                          accounts: context.watch<AccountProvider>().accounts,
                          categories: _drafts[i].parsed.isExpense
                              ? _expenseCategories
                              : _incomeCategories,
                          investmentTypes: _investmentTypes,
                          onChanged: () => setState(() {}),
                          onDismiss: () => _dismiss(_drafts[i]),
                          onShowRaw: () => _showRawMessage(_drafts[i]),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: ElevatedButton(
                          onPressed: selectedCount == 0 || _importing
                              ? null
                              : _importSelected,
                          child: _importing
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : Text('Import $selectedCount selected'),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  PopupMenuItem<_ScanSpan> _spanItem(_ScanSpan span, String label) {
    final selected = _span == span;
    return PopupMenuItem<_ScanSpan>(
      value: span,
      child: Row(
        children: [
          Icon(selected ? Icons.check : null, size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool permissionDenied;
  final String rangeLabel;
  final bool includeDismissed;
  final VoidCallback onRetry;
  const _EmptyState({
    required this.permissionDenied,
    required this.rangeLabel,
    required this.includeDismissed,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final supported = SmsService.isSupported;
    final String message;
    if (!supported) {
      message = 'SMS import works on Android only.';
    } else if (permissionDenied) {
      message = 'Finance Tracker needs permission to read SMS so it can find '
          'bank transaction alerts. Nothing is sent anywhere — messages are '
          'read on this device only.';
    } else {
      message = 'No new transactions found in $rangeLabel. Messages you '
          'already imported${includeDismissed ? '' : ' or dismissed'} are not '
          'shown again.'
          '${includeDismissed ? '' : ' Widen the range or show dismissed '
              'messages from the toolbar.'}';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(permissionDenied ? Icons.lock_outline : Icons.sms_outlined,
                size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (supported) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onRetry,
                child: Text(permissionDenied ? 'Grant permission' : 'Rescan'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DraftCard extends StatefulWidget {
  final SmsDraft draft;
  final List<Account> accounts;
  final List<String> categories;
  final List<String> investmentTypes;
  final VoidCallback onChanged;
  final VoidCallback onDismiss;
  final VoidCallback onShowRaw;

  const _DraftCard({
    super.key,
    required this.draft,
    required this.accounts,
    required this.categories,
    required this.investmentTypes,
    required this.onChanged,
    required this.onDismiss,
    required this.onShowRaw,
  });

  @override
  State<_DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends State<_DraftCard> {
  /// Whether the user picked "Other" and is now typing a value, for the
  /// category box and the investment-type box respectively. The dropdown
  /// otherwise shows a recalled/preset value directly.
  bool _categoryOther = false;
  bool _investTypeOther = false;

  final _customCategory = TextEditingController();
  final _customInvestType = TextEditingController();
  final _description = TextEditingController();

  @override
  void initState() {
    super.initState();
    _description.text = widget.draft.description;
  }

  @override
  void dispose() {
    _customCategory.dispose();
    _customInvestType.dispose();
    _description.dispose();
    super.dispose();
  }

  Widget _accountDropdown({
    required String label,
    required int? value,
    required String? errorText,
    required ValueChanged<int?> onChanged,
  }) =>
      DropdownButtonFormField<int?>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: label, errorText: errorText, isDense: true),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('None')),
          ...widget.accounts.map((a) => DropdownMenuItem<int?>(
              value: a.id,
              child: Text(a.name, overflow: TextOverflow.ellipsis))),
        ],
        onChanged: onChanged,
      );

  /// A dropdown of [options] that reveals a text box when "Other" is picked, so
  /// the user can name a category or an investment type not on the list. The
  /// chosen or typed value is written back through [onValue].
  Widget _pickerWithOther({
    required String label,
    required String current,
    required List<String> options,
    required bool isOther,
    required TextEditingController controller,
    required ValueChanged<bool> onOtherChanged,
    required ValueChanged<String> onValue,
  }) {
    // While typing a custom value the dropdown reads "Other"; otherwise it
    // shows the current value, added to the list if it isn't already there
    // (a category recalled from history the user once typed).
    final items = <String>{...options, if (!isOther) current};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: isOther ? _kOther : current,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: items
              .map((c) => DropdownMenuItem(
                  value: c,
                  child: Text(c, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            if (v == _kOther) {
              onOtherChanged(true);
              onValue(controller.text.trim());
            } else {
              onOtherChanged(false);
              onValue(v);
            }
          },
        ),
        if (isOther)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextField(
              controller: controller,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                  labelText: 'Enter ${label.toLowerCase()}', isDense: true),
              onChanged: (t) => onValue(t.trim()),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final parsed = draft.parsed;
    // A transfer is neither a gain nor a loss, so it gets neither colour.
    final amountColor = parsed.isTransfer
        ? null
        : (parsed.isExpense ? expenseColor(context) : incomeColor(context));
    final sign = parsed.isTransfer ? '' : (parsed.isExpense ? '−' : '+');
    // A message that named an account we could not resolve is the case most
    // likely to be filed wrongly, so it is called out rather than left to be
    // noticed in the dropdown. An investment carries no account, so the flag
    // doesn't apply there.
    final unmatchedLast4 =
        parsed.last4 != null && draft.accountId == null && !draft.asInvestment;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: draft.selected,
                  onChanged: (v) {
                    draft.selected = v ?? false;
                    widget.onChanged();
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Editable: the parsed merchant/sender is only a guess,
                      // so the user can give the row a name they recognise
                      // before it is posted.
                      TextField(
                        controller: _description,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.only(bottom: 2),
                          hintText: 'Description',
                        ),
                        onChanged: (v) => draft.description = v,
                      ),
                      Text(
                        '${formatIsoDate(parsed.date)} · ${parsed.sender}'
                        '${parsed.last4 != null ? ' · ••${parsed.last4}' : ''}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$sign${formatMoney(parsed.amount)}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: amountColor),
                ),
              ],
            ),
            if (draft.duplicateOf != null)
              _Notice(
                icon: Icons.content_copy,
                color: Colors.orange,
                text: 'Looks like "${draft.duplicateOf!.description}", which '
                    'you already entered. Left unchecked.',
              ),
            if (parsed.isTransfer)
              const _Notice(
                icon: Icons.swap_horiz,
                color: Colors.blueGrey,
                text: 'Money moved between your accounts — recorded as a '
                    'transfer, so it is not counted as spending.',
              ),
            if (draft.asInvestment)
              const _Notice(
                icon: Icons.trending_up,
                color: Colors.blueGrey,
                text: 'Recorded as an investment contribution, not as '
                    'spending.',
              ),
            if (draft.recalledCategory != null && !draft.asInvestment)
              _Notice(
                icon: Icons.history,
                color: Colors.blueGrey,
                text: 'Filed as ${draft.recalledCategory} last time.',
              ),
            // Only a plain debit can be reclassified as an investment.
            if (draft.canBeInvestment)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 0, 0),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  segments: const [
                    ButtonSegment(
                        value: false,
                        label: Text('Expense'),
                        icon: Icon(Icons.remove_circle_outline, size: 16)),
                    ButtonSegment(
                        value: true,
                        label: Text('Investment'),
                        icon: Icon(Icons.trending_up, size: 16)),
                  ],
                  selected: {draft.asInvestment},
                  onSelectionChanged: (s) {
                    setState(() => draft.asInvestment = s.first);
                    widget.onChanged();
                  },
                ),
              ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: draft.asInvestment
                  // An investment has no account and no category; the user
                  // picks the instrument instead.
                  ? _pickerWithOther(
                      label: 'Investment type',
                      current: draft.investmentType,
                      options: widget.investmentTypes,
                      isOther: _investTypeOther,
                      controller: _customInvestType,
                      onOtherChanged: (v) =>
                          setState(() => _investTypeOther = v),
                      onValue: (v) {
                        draft.investmentType = v;
                        widget.onChanged();
                      },
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _accountDropdown(
                            label: parsed.isTransfer ? 'From' : 'Account',
                            value: draft.accountId,
                            errorText: unmatchedLast4
                                ? 'No account with ••${parsed.last4}'
                                : null,
                            onChanged: (v) {
                              draft.accountId = v;
                              widget.onChanged();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          // A transfer needs the receiving account instead of a
                          // category; its category is fixed at "Transfer".
                          child: parsed.isTransfer
                              ? _accountDropdown(
                                  label: 'To',
                                  value: draft.toAccountId,
                                  errorText: draft.needsDestination
                                      ? (parsed.toLast4 != null
                                          ? 'No account with ••${parsed.toLast4}'
                                          : 'Pick the receiving account')
                                      : null,
                                  onChanged: (v) {
                                    draft.toAccountId = v;
                                    widget.onChanged();
                                  },
                                )
                              : _pickerWithOther(
                                  label: 'Category',
                                  current: draft.category,
                                  options: widget.categories,
                                  isOther: _categoryOther,
                                  controller: _customCategory,
                                  onOtherChanged: (v) =>
                                      setState(() => _categoryOther = v),
                                  onValue: (v) {
                                    draft.category = v;
                                    widget.onChanged();
                                  },
                                ),
                        ),
                      ],
                    ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.article_outlined, size: 16),
                  label: const Text('Message'),
                  onPressed: widget.onShowRaw,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Dismiss'),
                  onPressed: widget.onDismiss,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A one-line explanation under a draft's header — why it is unchecked, or
/// why it is being recorded as a transfer rather than as spending.
class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Notice({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 0, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }
}
