part of '../home_screen.dart';

/// The latest few transactions, whatever period the charts above show — so
/// "did that payment go in?" is answered on the dashboard, without switching
/// to the Transactions tab and scrolling. Hidden until there is something.
class _RecentTransactions extends StatelessWidget {
  final ExpenseProvider provider;
  final VoidCallback onSeeAll;
  const _RecentTransactions({required this.provider, required this.onSeeAll});

  static const _count = 5;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // Rows are kept newest first; skip anything dated ahead of today.
    final rows = provider.expenses
        .where((e) => !e.date.isAfter(now))
        .take(_count)
        .toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    final accounts = context.watch<AccountProvider>();
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: SectionHeader('Recent transactions')),
              TextButton(onPressed: onSeeAll, child: const Text('See all')),
            ],
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final e in rows)
                  _RecentRow(
                    expense: e,
                    symbol: accounts.accountById(e.accountId)?.symbol,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One compact row in [_RecentTransactions]; tap for edit/duplicate/delete.
class _RecentRow extends StatelessWidget {
  final Expense expense;

  /// The source account's currency symbol; null for the base currency.
  final String? symbol;
  const _RecentRow({required this.expense, this.symbol});

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final magnitude = symbol == null
        ? formatMoney(e.amount.abs())
        : formatMoneyIn(symbol!, e.amount.abs());
    // Same sign and colour conventions as the Transactions list.
    final moneyIn = e.isIncome || e.isRefund;
    final amount =
        e.isTransfer ? magnitude : '${moneyIn ? '+' : '-'}$magnitude';
    final color = moneyIn
        ? incomeColor(context)
        : e.isTransfer
            ? transferColor(context)
            : expenseColor(context);
    return ListTile(
      dense: true,
      leading: e.isTransfer
          ? CircleAvatar(
              radius: 16,
              backgroundColor: transferAvatarColor(context),
              child: Icon(Icons.swap_horiz,
                  size: 18, color: transferColor(context)),
            )
          : CategoryAvatar(category: e.category, radius: 16),
      title: Text(
        e.description.isEmpty ? '(no description)' : e.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${e.isTransfer ? 'Transfer' : e.category} · ${formatDateWithDay(e.date)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(amount,
          style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      onTap: () => transactionRowActions(context, e,
          onDelete: () => _deleteWithUndo(context, e)),
    );
  }

  /// Deletes [e] (picked explicitly from the row's action sheet) and offers
  /// an Undo that puts the same row back.
  static Future<void> _deleteWithUndo(BuildContext context, Expense e) async {
    final expenses = context.read<ExpenseProvider>();
    final accounts = context.read<AccountProvider>();
    final messenger = ScaffoldMessenger.of(context);
    await expenses.deleteExpense(e.id!);
    await accounts.refreshBalances();
    messenger.showSnackBar(SnackBar(
      content: const Text('Transaction deleted'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          await expenses.addExpense(e);
          await accounts.refreshBalances();
        },
      ),
    ));
  }
}

/// The transactions behind one pie slice: a total plus the rows that make it
/// up, shown when the user taps a category on the dashboard chart.
class _CategoryDetailSheet extends StatelessWidget {
  final String category;
  final String period;
  final int total;
  final List<Expense> rows;
  final int Function(Expense) baseAmountOf;
  final void Function(Expense) onEdit;

  const _CategoryDetailSheet({
    required this.category,
    required this.period,
    required this.total,
    required this.rows,
    required this.baseAmountOf,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: bottomSheetPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryAvatar(category: category, radius: 16),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(category,
                    style: Theme.of(context).textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis),
              ),
              Text(formatMoney(total),
                  style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: Space.xxs),
          Text(
            '$period · ${rows.length} transaction'
            '${rows.length == 1 ? '' : 's'}',
            style: TextStyle(
                color: mutedTextColor(context), fontSize: FontSizes.body),
          ),
          const Divider(height: 20),
          // Flexible + shrinkWrap keeps a short list compact but lets a long one
          // scroll inside the sheet rather than overflow.
          Flexible(
            child: rows.isEmpty
                ? Text('No transactions in this category.',
                    style: TextStyle(color: mutedTextColor(context)))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final e = rows[i];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            e.description.isEmpty
                                ? '(no description)'
                                : e.description,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(formatDateWithDay(e.date)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(formatMoney(baseAmountOf(e)),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(width: Space.xs),
                            Icon(Icons.chevron_right,
                                size: 18, color: mutedTextColor(context)),
                          ],
                        ),
                        // Tap a row to edit that transaction. onEdit closes
                        // this sheet and opens the editor over the dashboard, so
                        // the totals refresh with the change on save.
                        onTap: () => onEdit(e),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// The period's top three merchants under the category chart; hidden when
/// no expense names a merchant.
class _DashboardMerchants extends StatelessWidget {
  final List<Expense> rows;
  final int total;
  final int Function(Expense) baseAmountOf;
  const _DashboardMerchants({
    required this.rows,
    required this.total,
    required this.baseAmountOf,
  });

  @override
  Widget build(BuildContext context) {
    final merchants = topMerchants(rows, baseAmountOf, limit: 3);
    if (merchants.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: TopMerchantsCard(merchants: merchants, periodTotal: total),
    );
  }
}
