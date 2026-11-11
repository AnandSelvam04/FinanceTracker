import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/expense.dart';
import '../models/investment.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/investment_provider.dart';
import '../services/db_service.dart';
import '../utils/account_icons.dart';
import '../utils/account_ledger.dart';
import '../utils/app_colors.dart';
import '../utils/credit_card_summary.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/insets.dart';
import '../utils/ledger_cycles.dart';
import '../widgets/category_avatar.dart';
import '../widgets/empty_state.dart';
import '../widgets/hero_total_card.dart';
import '../widgets/reconcile_dialog.dart';
import '../widgets/transaction_edit_sheet.dart';

/// What the user asked for from the statement's app bar; the Accounts screen
/// owns the edit dialog and the delete confirmation, so it acts on these.
enum AccountDetailAction { edit, delete }

/// One account's statement: every transaction and investment that moved its
/// balance, newest first, each with the balance right after it.
///
/// The Accounts screen showed only a balance, so "why is my card at −₹42,000"
/// meant filtering the Transactions tab by account — which could not show the
/// running balance, and only covered the years already loaded.
class AccountDetailScreen extends StatefulWidget {
  final Account account;

  /// Whether the app bar offers Edit and Delete, which hand the choice back
  /// to the caller to act on. The dashboard opens the screen to read only.
  final bool showActions;
  const AccountDetailScreen(
      {super.key, required this.account, this.showActions = true});

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  List<Expense>? _transactions;
  late final ExpenseProvider _expenses;

  /// For a card with a billing cycle: rows grouped by cycle (the default) or
  /// as one list.
  bool _byCycle = true;

  int get _id => widget.account.id!;

  @override
  void initState() {
    super.initState();
    // Reload when a row is edited, duplicated or deleted from here (or
    // anywhere else while this screen is open).
    _expenses = context.read<ExpenseProvider>()..addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _expenses.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await DBService().getExpensesForAccount(_id);
    if (mounted) setState(() => _transactions = rows);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountProvider>();
    // The account may have been edited since this screen opened.
    final account = accounts.accountById(_id) ?? widget.account;
    final investments = context.watch<InvestmentProvider>().investments;
    final rows = _transactions;
    final ledger = rows == null
        ? null
        : accountLedger(
            accountId: _id,
            openingBalance: account.openingBalance,
            transactions: rows,
            investments: investments,
          );
    final balance = accounts.balanceOf(account) ??
        (ledger == null || ledger.isEmpty
            ? account.openingBalance
            : ledger.first.balanceAfter);
    final limitCaption = _limitCaption(accounts, account, balance);

    return Scaffold(
      appBar: AppBar(
        title: Text(account.name),
        actions: [
          if (widget.showActions) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit account',
              onPressed: () => Navigator.pop(context, AccountDetailAction.edit),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete account',
              onPressed: () =>
                  Navigator.pop(context, AccountDetailAction.delete),
            ),
          ],
        ],
      ),
      body: ledger == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: scrollPadding(context, all: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: HeroTotalCard(
                    label: account.type == 'credit_card'
                        ? 'Balance (negative = owed)'
                        : 'Balance',
                    amount: formatMoneySignedIn(account.symbol, balance),
                    badge: accountTypeIcon(account.type),
                    heroTag: 'account-$_id',
                    caption: [
                      Account.typeLabel(account.type),
                      if (account.last4 != null) '••${account.last4}',
                      if (limitCaption != null) limitCaption,
                      '${ledger.length} '
                          '${ledger.length == 1 ? 'entry' : 'entries'}',
                    ].join(' · '),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.balance, size: 18),
                      label: const Text('Match bank balance'),
                      onPressed: () => showReconcileDialog(context, account),
                    ),
                  ),
                ),
                if (ledger.isEmpty)
                  const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No transactions yet',
                    message: 'Spending, income and transfers on this account '
                        'appear here.',
                  ),
                if (account.hasBillingCycle && ledger.isNotEmpty) ...[
                  Center(
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: true, label: Text('By cycle')),
                        ButtonSegment(value: false, label: Text('All')),
                      ],
                      selected: {_byCycle},
                      onSelectionChanged: (v) =>
                          setState(() => _byCycle = v.first),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (account.hasBillingCycle && _byCycle)
                  for (final cycle in ledgerByCycle(ledger,
                      statementDay: account.statementDay!,
                      dueDay: account.dueDay!,
                      now: DateTime.now())) ...[
                    _CycleHeader(cycle: cycle, symbol: account.symbol),
                    for (final entry in cycle.entries)
                      _LedgerRow(
                          entry: entry, account: account, accounts: accounts),
                  ]
                else
                  for (final entry in ledger)
                    _LedgerRow(
                        entry: entry, account: account, accounts: accounts),
                _OpeningRow(
                    symbol: account.symbol, amount: account.openingBalance),
              ],
            ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  final AccountLedgerEntry entry;
  final Account account;
  final AccountProvider accounts;
  const _LedgerRow({
    required this.entry,
    required this.account,
    required this.accounts,
  });

  @override
  Widget build(BuildContext context) {
    final source = entry.source;
    final String title;
    final String subtitle;
    final Widget avatar;
    if (source is Investment) {
      title = source.name;
      subtitle = 'Investment · ${source.type}';
      avatar = CircleAvatar(
        radius: 18,
        backgroundColor: incomeAvatarColor(context),
        child: Icon(Icons.trending_up, size: 18, color: incomeColor(context)),
      );
    } else {
      final e = source as Expense;
      title = e.description.isEmpty ? '(no description)' : e.description;
      if (e.isTransfer) {
        final outgoing = e.accountId == account.id;
        final other =
            accounts.accountById(outgoing ? e.toAccountId : e.accountId)?.name;
        subtitle = other == null
            ? 'Transfer'
            : (outgoing ? 'Transfer to $other' : 'Transfer from $other');
        avatar = CircleAvatar(
          radius: 18,
          backgroundColor: transferAvatarColor(context),
          child:
              Icon(Icons.swap_horiz, size: 18, color: transferColor(context)),
        );
      } else {
        subtitle = e.isRefund ? '${e.category} · Refund' : e.category;
        avatar = CategoryAvatar(category: e.category, radius: 18);
      }
    }
    final into = entry.delta > 0;
    final amount = formatMoneyIn(account.symbol, entry.delta.abs());
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: avatar,
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('$subtitle · ${formatShortDate(entry.date)}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              entry.delta == 0 ? amount : '${into ? '+' : '−'}$amount',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: entry.delta == 0
                    ? null
                    : (into ? incomeColor(context) : expenseColor(context)),
              ),
            ),
            Text(
              formatMoneySignedIn(account.symbol, entry.balanceAfter),
              style: TextStyle(fontSize: 12, color: mutedTextColor(context)),
            ),
          ],
        ),
        // Transactions can be edited, duplicated or deleted from here;
        // investments are edited from the Investments screen.
        onTap: source is Expense
            ? () => transactionRowActions(context, source,
                onDelete: () => _delete(context, source))
            : null,
      ),
    );
  }

  Future<void> _delete(BuildContext context, Expense e) async {
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

/// Heads one billing cycle in a card's statement: which statement it is, the
/// dates it covers, and what was charged and paid in it.
class _CycleHeader extends StatelessWidget {
  final LedgerCycle cycle;
  final String symbol;
  const _CycleHeader({required this.cycle, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final muted = mutedTextColor(context);
    final c = cycle;
    final title = c.isOpen
        ? 'Current cycle'
        : 'Statement ${formatCompactDate(c.statementDate)}';
    final range = '${formatCompactDate(c.start)} – '
        '${formatCompactDate(c.statementDate)}'
        '${c.isOpen ? '' : ' · due ${formatCompactDate(c.dueDate)}'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                Text(range,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Spent ${formatMoneyIn(symbol, c.charged)}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: expenseColor(context))),
              if (c.paidIn > 0)
                Text('Paid in ${formatMoneyIn(symbol, c.paidIn)}',
                    style:
                        TextStyle(fontSize: 12, color: incomeColor(context))),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Limit ₹2,00,000 · 8% used" for a credit card with a limit; for one that
/// shares its limit with another card (a Visa + RuPay pair), the shared limit
/// and the share of it used across both. Null without a limit.
String? _limitCaption(AccountProvider accounts, Account account, int balance) {
  if (account.type != 'credit_card' || account.id == null) return null;
  final pool = limitPools(accounts.accounts)[account.id];
  final limit = pool?.limit ??
      (account.creditLimit != null && account.creditLimit! > 0
          ? account.creditLimit
          : null);
  if (limit == null) return null;
  int owed(Account a) {
    final b = a.id == account.id ? balance : (accounts.balanceOf(a) ?? 0);
    return b < 0 ? -b : 0;
  }

  final shared = pool != null && pool.isShared;
  final used =
      shared ? pool.cards.fold<int>(0, (s, c) => s + owed(c)) : owed(account);
  return [
    'Limit ${formatMoneyIn(account.symbol, limit)}',
    if (shared)
      'shared with ${pool.others(account).map((c) => c.name).join(', ')}',
    if (used > 0) '${(used * 100 / limit).round()}% used',
  ].join(' · ');
}

/// The last row: where the running balance starts.
class _OpeningRow extends StatelessWidget {
  final String symbol;
  final int amount;
  const _OpeningRow({required this.symbol, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Icon(Icons.flag_outlined, size: 18, color: mutedTextColor(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Opening balance',
                style: TextStyle(color: mutedTextColor(context))),
          ),
          Text(formatMoneySignedIn(symbol, amount),
              style: TextStyle(color: mutedTextColor(context))),
        ],
      ),
    );
  }
}
