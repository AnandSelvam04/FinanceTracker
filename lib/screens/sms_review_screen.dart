import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/investment.dart';
import '../models/recurring_rule.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/investment_provider.dart';
import '../providers/recurring_provider.dart';
import '../services/category_memory.dart';
import '../services/db_service.dart';
import '../services/investment_merchants.dart';
import '../services/recurring_detector.dart';
import '../services/recurring_service.dart';
import '../services/notification_service.dart';
import '../services/sms_service.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/db_constants.dart';
import '../utils/insets.dart';
import '../widgets/category_picker.dart';

part 'sms_review/draft_card.dart';
part 'sms_review/review_widgets.dart';

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

/// The spans a scan can cover: everything since the queue was last cleared
/// (the default), the presets, or a custom date range.
enum _ScanSpan { sinceReview, twoDays, week, month, custom }

class _SmsReviewScreenState extends State<SmsReviewScreen> {
  List<SmsDraft> _drafts = [];
  bool _loading = true;
  bool _importing = false;

  /// Null until a scan has run; set when the permission was refused, so the
  /// empty state can explain itself rather than claiming nothing was found.
  bool _permissionDenied = false;

  /// Asking again cannot help - see [SmsService.isPermissionBlocked].
  bool _permissionBlocked = false;

  /// Which span the next scan covers. [_customRange] carries the dates when
  /// this is [_ScanSpan.custom].
  _ScanSpan _span = _ScanSpan.sinceReview;
  DateTimeRange? _customRange;

  /// Where a [_ScanSpan.sinceReview] scan starts, worked out from the stored
  /// review mark when the scan runs.
  DateTime? _sinceReviewFrom;

  /// When the last scan ran, and whether it reached back at least to the
  /// review mark (so emptying its queue means everything up to then has been
  /// dealt with and the mark may move forward to it).
  DateTime? _scannedAt;
  bool _scanCoversBacklog = false;

  /// Whether the scan also surfaces messages the user dismissed before, so a
  /// wrongly dismissed one can be pulled back in and imported.
  bool _includeDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
    // The alerts caught as they arrived are all in the queue below.
    NotificationService.instance.cancelSmsCaptures();
  }

  @override
  void dispose() {
    // Leaving with the queue empty means every message the scan found was
    // imported or dismissed, so the next default scan can start from here.
    // Done on the way out rather than per action, so an Undo that puts a
    // message back before leaving keeps it inside the next scan.
    final scannedAt = _scannedAt;
    if (scannedAt != null &&
        _scanCoversBacklog &&
        !_loading &&
        _drafts.isEmpty) {
      SmsService.markReviewedThrough(scannedAt);
    }
    super.dispose();
  }

  /// Built-in investment types plus any the user already uses, "Other" last —
  /// the same list the Add Investment screen offers.
  List<String> get _investmentTypes {
    final base = Investment.builtInTypes.where((t) => t != _kOther).toList();
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
      case _ScanSpan.sinceReview:
        final from = _sinceReviewFrom;
        return (
          from: from,
          to: null,
          window: SmsService.defaultWindow,
          label: from == null
              ? 'in the last 2 days'
              : 'since ${formatShortDate(from)}'
        );
      case _ScanSpan.twoDays:
        return (
          from: null,
          to: null,
          window: const Duration(days: 2),
          label: 'in the last 2 days'
        );
      case _ScanSpan.week:
        return (
          from: null,
          to: null,
          window: const Duration(days: 7),
          label: 'in the last 7 days'
        );
      case _ScanSpan.month:
        return (
          from: null,
          to: null,
          window: const Duration(days: 30),
          label: 'in the last 30 days'
        );
      case _ScanSpan.custom:
        final r = _customRange!;
        // Include the whole of the end day, not just its first instant.
        final to = DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59);
        return (
          from: DateTime(r.start.year, r.start.month, r.start.day),
          to: to,
          window: SmsService.defaultWindow,
          label: 'in ${formatShortDate(r.start)} – ${formatShortDate(r.end)}'
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
    final blocked = granted ? false : await SmsService.isPermissionBlocked();
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _loading = false;
        _permissionDenied = true;
        _permissionBlocked = blocked;
        _drafts = [];
      });
      return;
    }

    final now = DateTime.now();
    final reviewedThrough = await SmsService.reviewedThrough();
    final backlogStart = SmsService.scanStartSince(reviewedThrough, now);
    _sinceReviewFrom = backlogStart;
    final range = _range;
    final found = await SmsService.scan(
      now: now,
      window: range.window,
      from: range.from,
      to: range.to,
      includeDismissed: _includeDismissed,
    );
    // Hand-entered rows near the scan window, so a message that duplicates one
    // can be flagged rather than silently recorded twice. Bounded to the
    // window the candidates can fall in (plus the duplicate tolerance either
    // side) rather than reading a ledger that grows without limit.
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
    // Merchants imported as investments before (a SIP, a broker), so their
    // alerts arrive already set to Investment with the same type and name.
    final investmentMemory = await SmsService.investmentMerchants();
    // Just over a year of history, so a monthly charge can be recognised across
    // enough prior months to suggest turning it into a recurring rule.
    final history = await DBService().getExpensesByDateRange(
      now.subtract(const Duration(days: 400)),
      now.add(const Duration(days: 1)),
    );
    if (!mounted) return;
    // Shared across the drafts so one hand-entered row is flagged as the
    // duplicate of at most one message.
    final claimed = <Object>{};
    setState(() {
      _permissionDenied = false;
      _permissionBlocked = false;
      _scannedAt = now;
      _scanCoversBacklog = range.to == null && !lower.isAfter(backlogStart);
      _drafts = [
        for (final p in found)
          SmsDraft.from(p, accountProvider.accounts,
              existing: existing,
              memory: memory,
              claimed: claimed,
              investmentMemory: investmentMemory,
              recurringSuggested: p.isExpense &&
                  RecurringDetector.looksMonthly(
                      p.description, p.amount, history,
                      asOf: now))
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
          DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
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
    // …and one with no source would credit the destination out of nothing:
    // a card bill payment names only the card, not the bank that paid it.
    final noSource = chosen.where((d) => d.needsSource).length;
    if (noSource > 0) {
      messenger.showSnackBar(SnackBar(
        content: Text('$noSource transfer'
            '${noSource == 1 ? ' needs the account' : 's need the accounts'} '
            'it was paid from.'),
      ));
      return;
    }

    final expenseProvider = context.read<ExpenseProvider>();
    final accountProvider = context.read<AccountProvider>();
    // A foreign charge ("USD 12.99") saved as it stands would be filed as
    // 12.99 in the account's own currency.
    final noAmount = chosen
        .where((d) =>
            (!d.isTransfer || d.asExpense) &&
            d.needsAmountFor(accountProvider.accountById(d.accountId)))
        .length;
    if (noAmount > 0) {
      messenger.showSnackBar(SnackBar(
        content: Text('Enter the amount in your account\'s currency for '
            '$noAmount foreign charge${noAmount == 1 ? '' : 's'}.'),
      ));
      return;
    }

    final investmentProvider = context.read<InvestmentProvider>();
    final recurringProvider = context.read<RecurringProvider>();

    final investmentDrafts =
        chosen.where((d) => d.asInvestment).toList(growable: false);
    final txDrafts =
        chosen.where((d) => !d.asInvestment).toList(growable: false);
    // A recurring rule only makes sense for a plain expense the user opted in
    // on; an investment or transfer is excluded.
    final recurringDrafts = chosen
        .where(
            (d) => d.createRecurring && !d.asInvestment && d.parsed.isExpense)
        .toList(growable: false);

    setState(() => _importing = true);
    try {
      // One transaction, matching the CSV importer: a failure part-way through
      // leaves nothing half-imported.
      if (txDrafts.isNotEmpty) {
        await expenseProvider
            .addExpenses([for (final d in txDrafts) d.toExpense()]);
      }
      // The investments table carries no sourceRef, so a contribution imported
      // from a message can't be deduped by the sourceRef check — mark its ref
      // as seen instead, so a rescan does not offer it again.
      for (final d in investmentDrafts) {
        await investmentProvider.addInvestment(d.toInvestment());
      }
      // Create a monthly rule for each opted-in draft, due next month — this
      // month's charge is the transaction just imported, so the rule must not
      // post it a second time.
      for (final d in recurringDrafts) {
        await recurringProvider.addRule(RecurringRule(
          description: d.description,
          amount: d.amount,
          category: d.category,
          type: DbConstants.txExpense,
          accountId: d.accountId,
          frequency: DbConstants.freqMonthly,
          nextDue: RecurringService.nextDate(
              d.parsed.date, DbConstants.freqMonthly, d.parsed.date.day),
        ));
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
      // Learn from the choice: a merchant imported as an investment arrives
      // pre-set next time; one switched back to Expense stops doing so.
      await SmsService.rememberInvestmentChoices(
        investments: investmentDrafts,
        expenses: txDrafts.where((d) => d.canBeInvestment),
      );
      await accountProvider.refreshBalances();
      if (!mounted) return;
      setState(() => _drafts.removeWhere((d) => d.selected));
      final ruleNote = recurringDrafts.isEmpty
          ? ''
          : ' Added ${recurringDrafts.length} recurring '
              'rule${recurringDrafts.length == 1 ? '' : 's'}.';
      messenger.showSnackBar(
        SnackBar(
            content: Text('Imported ${chosen.length} transaction'
                '${chosen.length == 1 ? '' : 's'}.$ruleNote')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _dismiss(SmsDraft draft) async {
    final messenger = ScaffoldMessenger.of(context);
    // Remember where it was so Undo can drop it back in place rather than at
    // the end of the list.
    final index = _drafts.indexOf(draft);
    setState(() => _drafts.remove(draft));
    await DBService().ignoreSourceRefs([draft.parsed.sourceRef]);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text('Dismissed "${draft.description}".'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          await DBService().unignoreSourceRefs([draft.parsed.sourceRef]);
          if (!mounted) return;
          setState(() => _drafts.insert(index.clamp(0, _drafts.length), draft));
        },
      ),
    ));
  }

  /// Dismisses every selected draft at once, remembering each one's ref so a
  /// later scan doesn't re-offer it. A single Undo restores the whole batch to
  /// where each row was.
  Future<void> _dismissSelected() async {
    final chosen = _selected;
    if (chosen.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    // Capture each dismissed draft with its original index (lowest first) so
    // Undo can drop the batch back in place rather than at the end.
    final removed = [
      for (final d in chosen) (index: _drafts.indexOf(d), draft: d),
    ]..sort((a, b) => a.index.compareTo(b.index));
    setState(() => _drafts.removeWhere((d) => d.selected));
    await DBService()
        .ignoreSourceRefs([for (final d in chosen) d.parsed.sourceRef]);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text('Dismissed ${chosen.length} '
          'message${chosen.length == 1 ? '' : 's'}.'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          await DBService()
              .unignoreSourceRefs([for (final d in chosen) d.parsed.sourceRef]);
          if (!mounted) return;
          setState(() {
            for (final r in removed) {
              _drafts.insert(r.index.clamp(0, _drafts.length), r.draft);
            }
          });
        },
      ),
    ));
  }

  /// Stops offering messages from [draft]'s merchant, and drops every draft
  /// from it now. Undo brings the merchant and its drafts back.
  Future<void> _ignoreMerchant(SmsDraft draft) async {
    final name = draft.parsed.description;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Always ignore $name?'),
        content: const Text('Messages from this merchant won\'t be offered '
            'again. Transactions already imported are kept. You can undo this '
            'from Ignored merchants in the menu.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ignore')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final key = await SmsService.ignoreMerchant(name);
    if (key == null || !mounted) return;
    final removed = [
      for (var i = 0; i < _drafts.length; i++)
        if (SmsService.isIgnored(_drafts[i].parsed, {key}))
          (index: i, draft: _drafts[i]),
    ];
    setState(() =>
        _drafts.removeWhere((d) => SmsService.isIgnored(d.parsed, {key})));
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text('Ignoring $name.'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          await SmsService.unignoreMerchant(key);
          if (!mounted) return;
          setState(() {
            for (final r in removed) {
              _drafts.insert(r.index.clamp(0, _drafts.length), r.draft);
            }
          });
        },
      ),
    ));
  }

  /// Lists the ignored merchants, each with a button to offer it again.
  Future<void> _manageIgnoredMerchants() async {
    var keys = (await SmsService.ignoredMerchants()).toList()..sort();
    if (!mounted) return;
    var changed = false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Ignored merchants'),
          content: SizedBox(
            width: double.maxFinite,
            child: keys.isEmpty
                ? const Text('None. Use "Always ignore" on a message to stop '
                    'seeing a merchant.')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final k in keys)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(k),
                          trailing: IconButton(
                            icon: const Icon(Icons.undo),
                            tooltip: 'Show again',
                            onPressed: () async {
                              await SmsService.unignoreMerchant(k);
                              changed = true;
                              setDialogState(() => keys = [...keys]..remove(k));
                            },
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close')),
          ],
        ),
      ),
    );
    if (changed && mounted) await _scan();
  }

  /// Selects or clears every draft at once.
  void _setAllSelected(bool selected) {
    setState(() {
      for (final d in _drafts) {
        d.selected = selected;
      }
    });
  }

  /// Applies one account to every draft that has an account field (its source
  /// account), so a queue of alerts from the same card doesn't need the
  /// account picked row by row. An investment's account is the one it was paid
  /// from, so it is set too.
  Future<void> _applyAccountToAll() async {
    final accounts = context.read<AccountProvider>().accounts;
    if (accounts.isEmpty) return;
    final chosen = await showDialog<int?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Set account for all'),
        children: [
          for (final a in accounts)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, a.id),
              child: Text(a.name),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      for (final d in _drafts) {
        d.accountId = chosen;
      }
    });
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
              _spanItem(_ScanSpan.sinceReview, 'Since last review'),
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
          PopupMenuButton<String>(
            tooltip: 'More',
            enabled: !busy,
            onSelected: (_) => _manageIgnoredMerchants(),
            itemBuilder: (context) => const [
              PopupMenuItem(
                  value: 'ignored', child: Text('Ignored merchants…')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _drafts.isEmpty
              ? _EmptyState(
                  permissionDenied: _permissionDenied,
                  permissionBlocked: _permissionBlocked,
                  rangeLabel: _range.label,
                  includeDismissed: _includeDismissed,
                  onRetry: _scan)
              : Column(
                  children: [
                    _BulkActionBar(
                      total: _drafts.length,
                      selected: selectedCount,
                      onSelectAll: () => _setAllSelected(true),
                      onSelectNone: () => _setAllSelected(false),
                      onSetAccount:
                          context.watch<AccountProvider>().accounts.isEmpty
                              ? null
                              : _applyAccountToAll,
                      onDismissSelected: selectedCount == 0 || _importing
                          ? null
                          : _dismissSelected,
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _drafts.length,
                        padding: scrollPadding(context, all: 12),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _DraftCard(
                          key: ValueKey(_drafts[i].parsed.sourceRef),
                          draft: _drafts[i],
                          accounts: context.watch<AccountProvider>().accounts,
                          investmentTypes: _investmentTypes,
                          onChanged: () => setState(() {}),
                          onDismiss: () => _dismiss(_drafts[i]),
                          onIgnoreMerchant: _drafts[i].isTransfer
                              ? null
                              : () => _ignoreMerchant(_drafts[i]),
                          onShowRaw: () => _showRawMessage(_drafts[i]),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: FilledButton(
                          onPressed: selectedCount == 0 || _importing
                              ? null
                              : _importSelected,
                          child: _importing
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
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
