import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/expense.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../services/db_service.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/insets.dart';
import '../utils/tags.dart';
import '../widgets/empty_state.dart';
import '../widgets/transaction_edit_sheet.dart';
import '../utils/font_sizes.dart';
import '../utils/dimens.dart';

/// Spending grouped by the #tags written in transaction notes — a trip, a
/// house move, reimbursable office spends — across categories and months.
class TagsScreen extends StatefulWidget {
  const TagsScreen({super.key});

  @override
  State<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends State<TagsScreen> {
  List<Expense>? _all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    // Every year, not just the loaded ones: a trip can be years back.
    final all = await DBService().getExpenses();
    if (mounted) setState(() => _all = all);
  }

  @override
  Widget build(BuildContext context) {
    final rates = context.watch<AccountProvider>().ratesByAccount;
    int toBase(Expense e) {
      final r = rates[e.accountId] ?? 1.0;
      return r == 1.0 ? e.amount : toBaseMinor(e.amount, r);
    }

    final all = _all;
    final tags = all == null ? null : tagSummaries(all, toBase);
    return Scaffold(
      appBar: AppBar(title: const Text('Tags')),
      body: tags == null
          ? const Center(child: CircularProgressIndicator())
          : tags.isEmpty
              ? const EmptyState(
                  icon: Icons.sell_outlined,
                  title: 'No tags yet',
                  message: 'Write a #tag in a transaction\'s note — #goa-trip, '
                      '#office, #wedding — and every transaction with it is '
                      'totalled here, whatever its category or month.',
                )
              : ListView(
                  padding: scrollPadding(context, all: Space.md),
                  children: [
                    for (final t in tags)
                      Card(
                        margin: const EdgeInsets.only(bottom: Space.sm),
                        child: ListTile(
                          leading: const Icon(Icons.sell_outlined),
                          title: Text('#${t.tag}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${t.transactions.length} transaction'
                              '${t.transactions.length == 1 ? '' : 's'}'
                              '${t.income > 0 ? ' · ${formatMoney(t.income)} in' : ''}'),
                          trailing: Text(formatMoney(t.spent),
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: expenseColor(context))),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => _TagDetail(tag: t.tag)),
                            );
                            await _load();
                          },
                        ),
                      ),
                  ],
                ),
    );
  }
}

/// One tag's transactions, newest first, with its total.
class _TagDetail extends StatefulWidget {
  final String tag;
  const _TagDetail({required this.tag});

  @override
  State<_TagDetail> createState() => _TagDetailState();
}

class _TagDetailState extends State<_TagDetail> {
  List<Expense>? _rows;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final all = await DBService().getExpenses();
    if (!mounted) return;
    setState(() => _rows = [
          for (final e in all)
            if (tagsOf(e).contains(widget.tag)) e
        ]..sort((a, b) => b.date.compareTo(a.date)));
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild after an edit made through the sheet.
    context.watch<ExpenseProvider>();
    final accounts = context.watch<AccountProvider>();
    final rows = _rows;
    final summary = rows == null
        ? null
        : tagSummaries(rows, (e) {
            final r = accounts.ratesByAccount[e.accountId] ?? 1.0;
            return r == 1.0 ? e.amount : toBaseMinor(e.amount, r);
          }).where((t) => t.tag == widget.tag).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text('#${widget.tag}')),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: scrollPadding(context, all: Space.md),
              children: [
                if (summary != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.lg),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                                '${rows.length} transaction'
                                '${rows.length == 1 ? '' : 's'}',
                                style:
                                    TextStyle(color: mutedTextColor(context))),
                          ),
                          Text('Spent ${formatMoney(summary.spent)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: FontSizes.bodyLarge)),
                        ],
                      ),
                    ),
                  ),
                for (final e in rows)
                  ListTile(
                    title: Text(e.description,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle:
                        Text('${formatCompactDate(e.date)} · ${e.category}'),
                    trailing: Text(
                      formatMoneyIn(
                          accounts.accountById(e.accountId)?.symbol ??
                              CurrencyFormat.symbol,
                          e.amount),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: e.isIncome
                              ? incomeColor(context)
                              : (e.isExpense ? expenseColor(context) : null)),
                    ),
                    onTap: () async {
                      await editTransactionSheet(context, e);
                      await _load();
                    },
                  ),
              ],
            ),
    );
  }
}
