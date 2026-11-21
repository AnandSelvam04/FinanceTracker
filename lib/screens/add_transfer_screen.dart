import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../models/expense.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';
import '../utils/insets.dart';
import '../widgets/amount_calculator_bar.dart';
import '../widgets/date_field_row.dart';
import '../widgets/empty_state.dart';
import 'accounts_screen.dart';
import '../utils/dimens.dart';
import '../utils/error_message.dart';

class AddTransferScreen extends StatefulWidget {
  /// A transfer to copy: accounts, amounts and note are filled in and the
  /// date is today, so only what differs needs changing.
  final Expense? duplicateOf;

  /// Opens with the destination (e.g. a credit card whose bill is being
  /// paid) and amount already filled in.
  final int? initialToAccountId;
  final int? initialAmount;

  /// Opens with the source filled in (money coming back from a loan to
  /// someone, say), and a note.
  final int? initialFromAccountId;
  final String? initialNote;

  const AddTransferScreen({
    super.key,
    this.duplicateOf,
    this.initialToAccountId,
    this.initialAmount,
    this.initialFromAccountId,
    this.initialNote,
  });

  @override
  State<AddTransferScreen> createState() => _AddTransferScreenState();
}

class _AddTransferScreenState extends State<AddTransferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _toAmountController = TextEditingController();
  final _noteController = TextEditingController();
  int? _fromAccountId;
  int? _toAccountId;
  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final copy = widget.duplicateOf;
    final accounts = context.read<AccountProvider>();
    // Only accounts that still exist: a dropdown whose value matches no item
    // throws.
    int? live(int? id) => accounts.accountById(id)?.id;
    if (copy != null) {
      _fromAccountId = live(copy.accountId);
      _toAccountId = live(copy.toAccountId);
      _amountController.text = minorToEditString(copy.amount);
      if (copy.toAmount != null) {
        _toAmountController.text = minorToEditString(copy.toAmount!);
      }
      if (copy.description != 'Transfer') {
        _noteController.text = copy.description;
      }
    } else {
      _toAccountId = live(widget.initialToAccountId);
      _fromAccountId = live(widget.initialFromAccountId);
      if (widget.initialNote != null) {
        _noteController.text = widget.initialNote!;
      }
      if (widget.initialAmount != null) {
        _amountController.text = minorToEditString(widget.initialAmount!);
      }
      // Paying something: start from the default account, when that isn't
      // the destination itself.
      final defaultId = live(context.read<SettingsProvider>().defaultAccountId);
      if (_fromAccountId == null &&
          _toAccountId != null &&
          defaultId != _toAccountId) {
        _fromAccountId = defaultId;
      }
    }
    // The To list leaves the source out, so the two can't start the same.
    if (_toAccountId != null && _toAccountId == _fromAccountId) {
      _toAccountId = null;
    }
    // Typed or worked out with the calculator keys alike.
    _amountController.addListener(_suggestFor);
  }

  @override
  void dispose() {
    _amountController.removeListener(_suggestFor);
    _amountController.dispose();
    _toAmountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Pre-fills the destination amount from the accounts' exchange rates so
  /// the user only has to adjust it when the actual rate differed.
  void _suggestToAmount(Account? from, Account? to) {
    if (from == null || to == null || to.rate == 0) return;
    final amount = parseMajor(_amountController.text);
    if (amount == null) return;
    final received = amount * from.rate / to.rate;
    _toAmountController.text = received.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final accountProvider = context.watch<AccountProvider>();
    // Archived accounts stay out, unless this (a duplicate) names one.
    final accounts = accountProvider.pickable([_fromAccountId, _toAccountId]);
    final fromAccount = accountProvider.accountById(_fromAccountId);
    final toAccount = accountProvider.accountById(_toAccountId);
    // A second, destination-currency amount is only needed when the two
    // accounts are held in different currencies.
    final crossCurrency = fromAccount != null &&
        toAccount != null &&
        fromAccount.symbol != toAccount.symbol;

    // The closed field shows just the name; the open list adds each
    // balance, so it is clear whether there is enough in it.
    Widget name(Account a) => Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(a.name, overflow: TextOverflow.ellipsis),
        );

    DropdownMenuItem<int> item(Account a) {
      final balance = accountProvider.balanceOf(a);
      return DropdownMenuItem(
        value: a.id,
        child: Text(
            balance == null
                ? a.name
                : '${a.name} · ${formatMoneySignedIn(a.symbol, balance)}',
            overflow: TextOverflow.ellipsis),
      );
    }

    return Scaffold(
      appBar: AppBar(
          title: Text(widget.duplicateOf != null
              ? 'Duplicate transfer'
              : 'Transfer between accounts')),
      body: accounts.length < 2
          ? EmptyState(
              icon: Icons.swap_horiz,
              title: 'Add another account',
              message: 'A transfer moves money between two of your accounts '
                  '— a card bill paid from the bank, or cash taken out.',
              actionLabel: 'Add account',
              onAction: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AccountsScreen(openAdd: true))),
            )
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(Space.lg),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        // The fields sat flush against each other with no gap.
                        spacing: 12,
                        children: [
                          DropdownButtonFormField<int>(
                            // Keyed on the value so a swap shows.
                            key: ValueKey('from-$_fromAccountId'),
                            isExpanded: true,
                            initialValue: _fromAccountId,
                            decoration: const InputDecoration(
                                labelText: 'From account'),
                            items: [for (final a in accounts) item(a)],
                            selectedItemBuilder: (_) =>
                                [for (final a in accounts) name(a)],
                            validator: (v) =>
                                v == null ? 'Select an account' : null,
                            onChanged: (v) => setState(() {
                              // Picking the destination as the source swaps
                              // the two rather than leaving them the same.
                              if (v != null && v == _toAccountId) {
                                _toAccountId = _fromAccountId;
                              }
                              _fromAccountId = v;
                              _suggestFor();
                            }),
                          ),
                          Align(
                            alignment: Alignment.center,
                            child: IconButton.outlined(
                              icon: const Icon(Icons.swap_vert),
                              tooltip: 'Swap from and to',
                              onPressed: () => setState(() {
                                final from = _fromAccountId;
                                _fromAccountId = _toAccountId;
                                _toAccountId = from;
                                _suggestFor();
                              }),
                            ),
                          ),
                          DropdownButtonFormField<int>(
                            key: ValueKey('to-$_toAccountId-$_fromAccountId'),
                            isExpanded: true,
                            initialValue: _toAccountId,
                            decoration:
                                const InputDecoration(labelText: 'To account'),
                            // Not the source: money can't move to where it
                            // already is.
                            items: [
                              for (final a in accounts)
                                if (a.id != _fromAccountId) item(a),
                            ],
                            selectedItemBuilder: (_) => [
                              for (final a in accounts)
                                if (a.id != _fromAccountId) name(a),
                            ],
                            validator: (v) {
                              if (v == null) return 'Select an account';
                              if (v == _fromAccountId) {
                                return 'Must differ from source account';
                              }
                              return null;
                            },
                            onChanged: (v) => setState(() {
                              _toAccountId = v;
                              _suggestFor();
                            }),
                          ),
                          TextFormField(
                            controller: _amountController,
                            decoration: InputDecoration(
                              labelText: crossCurrency
                                  ? 'Amount (${fromAccount.symbol})'
                                  : 'Amount',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            validator: validateAmountField,
                          ),
                          AmountCalculatorBar(controller: _amountController),
                          if (crossCurrency)
                            TextFormField(
                              controller: _toAmountController,
                              decoration: InputDecoration(
                                labelText:
                                    'Amount received (${toAccount.symbol})',
                                helperText:
                                    '${fromAccount.symbol} → ${toAccount.symbol}',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              validator: validateAmountField,
                            ),
                          TextFormField(
                            controller: _noteController,
                            decoration: const InputDecoration(
                                labelText: 'Note (optional)'),
                          ),
                          DateFieldRow(
                            date: _selectedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                            onChanged: (d) => setState(() => _selectedDate = d),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Pinned under the form, as on Add expense, so it is in reach
                // without scrolling.
                Padding(
                  padding: EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg,
                      safeBottom(context, extra: Space.md)),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _isSaving ? null : () => _save(context),
                      child: _isSaving
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            )
                          : const Text('Record transfer'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// Re-suggests the received amount for the accounts now chosen.
  void _suggestFor() {
    final accounts = context.read<AccountProvider>();
    final from = accounts.accountById(_fromAccountId);
    final to = accounts.accountById(_toAccountId);
    if (from != null && to != null && from.symbol != to.symbol) {
      _suggestToAmount(from, to);
    }
  }

  Future<void> _save(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final note = _noteController.text.trim();
    final accountProvider0 = context.read<AccountProvider>();
    final from = accountProvider0.accountById(_fromAccountId);
    final to = accountProvider0.accountById(_toAccountId);
    final crossCurrency =
        from != null && to != null && from.symbol != to.symbol;
    final transfer = Expense(
      description: note.isEmpty ? 'Transfer' : note,
      amount: parseMinor(_amountController.text)!,
      date: _selectedDate,
      category: 'Transfer',
      paymentMode: 'Other',
      type: DbConstants.txTransfer,
      accountId: _fromAccountId,
      toAccountId: _toAccountId,
      // Destination-currency amount, only for cross-currency transfers.
      toAmount: crossCurrency ? parseMinor(_toAmountController.text)! : null,
    );
    final expenseProvider = context.read<ExpenseProvider>();
    final accountProvider = context.read<AccountProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await expenseProvider.addExpense(transfer);
      await accountProvider.refreshBalances();
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: const Text('Transfer recorded')),
        );
        Navigator.pop(context);
      }
    } catch (e, st) {
      // A failed save used to vanish silently, leaving the user unsure
      // whether the money had been recorded.
      messenger.showSnackBar(SnackBar(
          content: Text(friendlyError("Couldn't record the transfer", e, st))));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
