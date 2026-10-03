import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/expense.dart';
import '../models/investment.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/investment_provider.dart';
import '../services/db_service.dart';
import '../utils/account_ledger.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/insets.dart';
import '../widgets/category_avatar.dart';
import '../widgets/empty_state.dart';
import '../widgets/hero_total_card.dart';
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
  const AccountDetailScreen({super.key, required this.account});

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  List<Expense>? _transactions;
  late final ExpenseProvider _expenses;

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

    return Scaffold(
      appBar: AppBar(
        title: Text(account.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit account',
            onPressed: () => Navigator.pop(context, AccountDetailAction.edit),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete account',
            onPressed: () => Navigator.pop(context, AccountDetailAction.delete),
          ),
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
                    caption: [
                      Account.typeLabel(account.type),
                      if (account.last4 != null) '••${account.last4}',
                      '${ledger.length} '
                          '${ledger.length == 1 ? 'entry' : 'entries'}',
                    ].join(' · '),
                  ),
                ),
                if (ledger.isEmpty)
                  const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No transactions yet',
                    message: 'Spending, income and transfers on this account '
                        'appear here.',
                  ),
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
