import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/emi_plan.dart';
import '../models/expense.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../services/db_service.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/db_constants.dart';
import '../utils/debt_summary.dart';
import '../utils/insets.dart';
import '../widgets/celebration.dart';
import '../widgets/empty_state.dart';
import 'account_detail_screen.dart';
import 'add_transfer_screen.dart';
import '../utils/font_sizes.dart';
import '../utils/dimens.dart';

/// Money you owe (a personal loan, or borrowed from a friend) and money
/// owed to you (lent to someone), each with what is left and how much has
/// been repaid.
///
/// Each is an account of type `loan` or `lent`, so borrowing, lending and
/// repaying are ordinary transfers: balances and net worth stay right with
/// no special cases, and none of it counts as spending or income.
class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  Map<int, ({int inflow, int outflow})>? _io;

  /// Card EMI plans, by the loan account that holds their principal.
  Map<int, EmiPlan> _emis = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    if (!mounted) return;
    await context.read<AccountProvider>().fetchAccounts();
    final io = await DBService().getAccountInOut();
    final plans = await DBService().getEmiPlans();
    if (mounted) {
      setState(() {
        _io = io;
        _emis = {for (final p in plans) p.loanAccountId: p};
      });
    }
  }

  List<DebtSummary> _summaries(AccountProvider accounts) => [
        for (final a in accounts.accounts)
          if (a.isLoan || a.isLent)
            debtSummary(
                a, accounts.balanceOf(a) ?? a.openingBalance, _io?[a.id])!
      ];

  Future<void> _open(Widget screen) async {
    final accounts = context.read<AccountProvider>();
    final settledBefore = {
      for (final s in _summaries(accounts))
        if (s.settled) s.account.id,
    };
    final knownBefore = {for (final s in _summaries(accounts)) s.account.id};
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    await _reload();
    if (!mounted) return;
    // A loan cleared by what was just recorded is worth marking.
    for (final s in _summaries(accounts)) {
      if (s.settled &&
          knownBefore.contains(s.account.id) &&
          !settledBefore.contains(s.account.id)) {
        celebrate(
            context,
            s.account.isLoan
                ? '${s.account.name} is fully repaid!'
                : '${s.account.name} has paid you back in full!');
        break;
      }
    }
  }

  Future<void> _add(String type) async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => _NewDebtDialog(type: type),
    );
    if (added == true) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountProvider>();
    final io = _io;
    final summaries = _summaries(accounts);
    final owe = summaries.where((s) => s.account.isLoan).toList()
      ..sort((a, b) => b.outstanding.compareTo(a.outstanding));
    final owed = summaries.where((s) => s.account.isLent).toList()
      ..sort((a, b) => b.outstanding.compareTo(a.outstanding));

    return Scaffold(
      appBar: AppBar(title: const Text('Loans & lending')),
      floatingActionButton: summaries.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddChoice(),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
      body: io == null
          ? const Center(child: CircularProgressIndicator())
          : summaries.isEmpty
              ? ListView(
                  children: [
                    EmptyState(
                      icon: Icons.handshake_outlined,
                      title: 'No loans yet',
                      message: 'Track a personal loan or money borrowed from '
                          'someone, and money you lent to friends — with '
                          'what is left to repay.',
                      actionLabel: 'I borrowed money',
                      onAction: () => _add('loan'),
                    ),
                    Center(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.handshake_outlined),
                        label: const Text('I lent money'),
                        onPressed: () => _add('lent'),
                      ),
                    ),
                  ],
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    padding: scrollPadding(context, all: Space.md),
                    children: [
                      _Totals(owe: owe, owed: owed),
                      if (owe.isNotEmpty) ...[
                        const _Heading('I owe'),
                        for (final s in owe)
                          _DebtTile(
                            summary: s,
                            emi: _emis[s.account.id],
                            emiCard: accounts
                                .accountById(_emis[s.account.id]?.cardId),
                            onOpen: () => _open(AccountDetailScreen(
                                account: s.account, showActions: false)),
                            onRepay: () => _open(AddTransferScreen(
                              initialToAccountId: s.account.id,
                              initialNote: 'Repayment · ${s.account.name}',
                            )),
                            onMore: () => _open(AddTransferScreen(
                              initialFromAccountId: s.account.id,
                              initialNote: 'Borrowed · ${s.account.name}',
                            )),
                          ),
                      ],
                      if (owed.isNotEmpty) ...[
                        const _Heading('Owed to me'),
                        for (final s in owed)
                          _DebtTile(
                            summary: s,
                            onOpen: () => _open(AccountDetailScreen(
                                account: s.account, showActions: false)),
                            onRepay: () => _open(AddTransferScreen(
                              initialFromAccountId: s.account.id,
                              initialNote: 'Paid back · ${s.account.name}',
                            )),
                            onMore: () => _open(AddTransferScreen(
                              initialToAccountId: s.account.id,
                              initialNote: 'Lent · ${s.account.name}',
                            )),
                          ),
                      ],
                      const SizedBox(height: 72),
                    ],
                  ),
                ),
    );
  }

  Future<void> _showAddChoice() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.request_quote_outlined),
              title: const Text('I borrowed money'),
              subtitle: const Text('A loan, or from a friend or family'),
              onTap: () => Navigator.pop(context, 'loan'),
            ),
            ListTile(
              leading: const Icon(Icons.handshake_outlined),
              title: const Text('I lent money'),
              subtitle: const Text('Someone owes you'),
              onTap: () => Navigator.pop(context, 'lent'),
            ),
          ],
        ),
      ),
    );
    if (type != null) await _add(type);
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            const EdgeInsets.fromLTRB(Space.xs, Space.lg, Space.xs, Space.sm),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
      );
}

/// What is owed each way, in the base currency.
class _Totals extends StatelessWidget {
  final List<DebtSummary> owe;
  final List<DebtSummary> owed;
  const _Totals({required this.owe, required this.owed});

  @override
  Widget build(BuildContext context) {
    int sum(List<DebtSummary> l) => l.fold<int>(
        0, (t, s) => t + toBaseMinor(s.outstanding, s.account.rate));
    Widget figure(String label, int v, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: FontSizes.caption,
                      color: mutedTextColor(context))),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(formatMoney(v),
                    style: TextStyle(
                        fontSize: FontSizes.title,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Row(
          children: [
            figure('I owe', sum(owe), expenseColor(context)),
            figure('Owed to me', sum(owed), incomeColor(context)),
          ],
        ),
      ),
    );
  }
}

class _DebtTile extends StatelessWidget {
  final DebtSummary summary;

  /// Set for a card EMI: it is repaid through the card's bill.
  final EmiPlan? emi;
  final Account? emiCard;
  final VoidCallback onOpen;
  final VoidCallback onRepay;
  final VoidCallback onMore;
  const _DebtTile({
    required this.summary,
    this.emi,
    this.emiCard,
    required this.onOpen,
    required this.onRepay,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final symbol = s.account.symbol;
    final isLoan = s.account.isLoan;
    final muted = mutedTextColor(context);
    final color = isLoan ? expenseColor(context) : incomeColor(context);
    return Card(
      margin: const EdgeInsets.only(bottom: Space.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(s.account.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: FontSizes.bodyLarge)),
                  ),
                  const SizedBox(width: Space.sm),
                  Text(
                    s.settled
                        ? 'Settled ✓'
                        : formatMoneyIn(symbol, s.outstanding),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: FontSizes.bodyLarge,
                        color: s.settled ? incomeColor(context) : color),
                  ),
                ],
              ),
              if (s.progress != null) ...[
                const SizedBox(height: Space.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.xs),
                  child: LinearProgressIndicator(
                    value: s.progress,
                    minHeight: 6,
                    color: incomeColor(context),
                    backgroundColor:
                        incomeColor(context).withValues(alpha: 0.18),
                  ),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  '${formatMoneyIn(symbol, s.repaid)} '
                  '${isLoan ? 'repaid' : 'paid back'} of '
                  '${formatMoneyIn(symbol, s.total)} '
                  '${isLoan ? 'borrowed' : 'lent'}'
                  '${s.overpaid > 0 ? ' · ${formatMoneyIn(symbol, s.overpaid)} over' : ''}',
                  style: TextStyle(fontSize: FontSizes.caption, color: muted),
                ),
              ],
              if (emi != null)
                Padding(
                  padding:
                      const EdgeInsets.only(top: Space.sm, bottom: Space.sm),
                  child: Text(
                    '${formatMoneyIn(symbol, emi!.monthlyAmount)}/month on '
                    '${emiCard?.name ?? 'the card'}\'s bill · '
                    '${emi!.billedBy(DateTime.now())} of ${emi!.months} '
                    'billed',
                    style: TextStyle(fontSize: FontSizes.caption, color: muted),
                  ),
                )
              else
                Wrap(
                  spacing: 4,
                  children: [
                    if (!s.settled)
                      TextButton.icon(
                        icon: const Icon(Icons.payments_outlined, size: 18),
                        label:
                            Text(isLoan ? 'Record repayment' : 'Got paid back'),
                        onPressed: onRepay,
                      ),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(isLoan ? 'Borrowed more' : 'Lent more'),
                      onPressed: onMore,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "I borrowed" / "I lent": who or what, how much, and which of your
/// accounts the money came into or went out of. With an account, that is
/// recorded as a transfer (the bank balance moves); without one — a loan
/// from before you started tracking — it becomes the starting amount.
class _NewDebtDialog extends StatefulWidget {
  final String type;
  const _NewDebtDialog({required this.type});

  @override
  State<_NewDebtDialog> createState() => _NewDebtDialogState();
}

class _NewDebtDialogState extends State<_NewDebtDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  int? _accountId;
  DateTime _date = DateTime.now();
  bool _saving = false;

  bool get _isLoan => widget.type == 'loan';

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final amount = parseMinor(_amount.text.trim())!;
    final accounts = context.read<AccountProvider>();
    final expenses = context.read<ExpenseProvider>();
    final via = accounts.accountById(_accountId);
    final id = await accounts.addAccount(Account(
      name: _name.text.trim(),
      type: widget.type,
      currency: via?.currency,
      rate: via?.rate ?? 1.0,
      // Not through an account: the debt starts at this amount.
      openingBalance: via != null ? 0 : (_isLoan ? -amount : amount),
    ));
    if (via != null) {
      await expenses.addExpense(Expense(
        description: _isLoan
            ? 'Borrowed · ${_name.text.trim()}'
            : 'Lent · ${_name.text.trim()}',
        amount: amount,
        date: _date,
        category: 'Transfer',
        paymentMode: 'Other',
        type: DbConstants.txTransfer,
        // Borrowing: loan → bank. Lending: bank → money lent.
        accountId: _isLoan ? id : via.id,
        toAccountId: _isLoan ? via.id : id,
      ));
    }
    await accounts.fetchAccounts();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context
        .watch<AccountProvider>()
        .accounts
        .where((a) => !a.isLoan && !a.isLent)
        .toList();
    return AlertDialog(
      title: Text(_isLoan ? 'I borrowed money' : 'I lent money'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: _isLoan ? 'From whom, or which loan' : 'To whom',
                  hintText:
                      _isLoan ? 'e.g. SBI personal loan, Ravi' : 'e.g. Ravi',
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Give it a name' : null,
              ),
              const SizedBox(height: Space.md),
              TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Amount (${CurrencyFormat.symbol})',
                ),
                validator: (v) {
                  final n = parseMinor((v ?? '').trim());
                  return n == null || n <= 0 ? 'Enter an amount' : null;
                },
              ),
              const SizedBox(height: Space.md),
              DropdownButtonFormField<int?>(
                initialValue: _accountId,
                isExpanded: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: _isLoan ? 'Money came into' : 'Money went from',
                  helperText: 'Pick "Not through an account" for a loan '
                      'from before you started tracking',
                  helperMaxLines: 2,
                ),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('Not through an account')),
                  for (final a in accounts)
                    DropdownMenuItem<int?>(
                        value: a.id,
                        child: Text(a.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              ),
              if (_accountId != null) ...[
                const SizedBox(height: Space.sm),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: Text(formatCompactDate(_date)),
                  subtitle: const Text('Date'),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
