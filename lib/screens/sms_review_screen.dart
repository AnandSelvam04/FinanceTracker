import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../services/db_service.dart';
import '../services/sms_service.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/insets.dart';

/// Review queue for transactions found in bank SMS alerts.
///
/// Nothing is posted without an explicit Import: the parser matches templates
/// banks change without notice, so a bad match must cost a tap rather than a
/// wrong balance. Dismissed messages are remembered (see
/// [DBService.ignoreSourceRefs]) so a later scan does not offer them again.
class SmsReviewScreen extends StatefulWidget {
  const SmsReviewScreen({super.key});

  @override
  State<SmsReviewScreen> createState() => _SmsReviewScreenState();
}

class _SmsReviewScreenState extends State<SmsReviewScreen> {
  static const _expenseCategories = [
    'Food', 'Transport', 'Shopping', 'Bills', //
    'Entertainment', 'Health', 'Education', 'Other',
  ];
  static const _incomeCategories = [
    'Salary', 'Business', 'Interest', 'Dividends', 'Gift', 'Refund', 'Other',
  ];

  List<SmsDraft> _drafts = [];
  bool _loading = true;
  bool _importing = false;

  /// Null until a scan has run; set when the permission was refused, so the
  /// empty state can explain itself rather than claiming nothing was found.
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
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

    final found = await SmsService.scan();
    // Hand-entered rows near the scan window, so a message that duplicates one
    // can be flagged rather than silently recorded twice.
    final existing = await DBService().getExpenses();
    if (!mounted) return;
    setState(() {
      _permissionDenied = false;
      _drafts = [
        for (final p in found)
          SmsDraft.from(p, accountProvider.accounts, existing: existing)
      ];
      _loading = false;
    });
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

    setState(() => _importing = true);
    try {
      // One transaction, matching the CSV importer: a failure part-way through
      // leaves nothing half-imported.
      await DBService().insertExpenses([for (final d in chosen) d.toExpense()]);
      // A collapsed pair posts one row but consumes two messages; the absorbed
      // one has to be marked seen or the next scan offers it on its own.
      await DBService().ignoreSourceRefs(
          [for (final d in chosen) ...d.parsed.alsoCoversRefs]);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import from SMS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rescan inbox',
            onPressed: _loading || _importing ? null : _scan,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _drafts.isEmpty
              ? _EmptyState(
                  permissionDenied: _permissionDenied, onRetry: _scan)
              : Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        itemCount: _drafts.length,
                        padding: scrollPadding(context, all: 12),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _DraftCard(
                          draft: _drafts[i],
                          accounts: context.watch<AccountProvider>().accounts,
                          categories: _drafts[i].parsed.isExpense
                              ? _expenseCategories
                              : _incomeCategories,
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
}

class _EmptyState extends StatelessWidget {
  final bool permissionDenied;
  final VoidCallback onRetry;
  const _EmptyState({required this.permissionDenied, required this.onRetry});

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
      message = 'No new transactions found in the last 90 days. Messages you '
          'already imported or dismissed are not shown again.';
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

class _DraftCard extends StatelessWidget {
  final SmsDraft draft;
  final List<Account> accounts;
  final List<String> categories;
  final VoidCallback onChanged;
  final VoidCallback onDismiss;
  final VoidCallback onShowRaw;

  const _DraftCard({
    required this.draft,
    required this.accounts,
    required this.categories,
    required this.onChanged,
    required this.onDismiss,
    required this.onShowRaw,
  });

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
          ...accounts.map((a) => DropdownMenuItem<int?>(
              value: a.id,
              child: Text(a.name, overflow: TextOverflow.ellipsis))),
        ],
        onChanged: onChanged,
      );

  @override
  Widget build(BuildContext context) {
    final parsed = draft.parsed;
    // A transfer is neither a gain nor a loss, so it gets neither colour.
    final amountColor = parsed.isTransfer
        ? null
        : (parsed.isExpense ? expenseColor(context) : incomeColor(context));
    final sign = parsed.isTransfer ? '' : (parsed.isExpense ? '−' : '+');
    // A message that named an account we could not resolve is the case most
    // likely to be filed wrongly, so it is called out rather than left to be
    // noticed in the dropdown.
    final unmatchedLast4 = parsed.last4 != null && draft.accountId == null;

    return Card(
      elevation: 2,
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
                    onChanged();
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(parsed.description,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15),
                          overflow: TextOverflow.ellipsis),
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
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
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
                        onChanged();
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
                              onChanged();
                            },
                          )
                        : DropdownButtonFormField<String>(
                            initialValue: categories.contains(draft.category)
                                ? draft.category
                                : categories.last,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Category', isDense: true),
                            items: categories
                                .map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c,
                                        overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (v) {
                              draft.category = v ?? draft.category;
                              onChanged();
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
                  onPressed: onShowRaw,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Dismiss'),
                  onPressed: onDismiss,
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
