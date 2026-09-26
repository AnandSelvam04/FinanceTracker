import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/expense.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../services/db_service.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/db_constants.dart';
import '../utils/insets.dart';
import 'dispose_with_route.dart';

/// Opens the right edit sheet for [expense] — a transfer editor for transfers,
/// the expense/income editor otherwise. Shared so every list of transactions
/// (the Transactions screen and the dashboard's category drill-down) edits a
/// row the same way instead of each re-implementing the form.
///
/// [firstDate] is the earliest date the date picker allows; callers that know
/// how far back their data goes pass it, others fall back to the year 2000.
Future<void> editTransactionSheet(
  BuildContext context,
  Expense expense, {
  DateTime? firstDate,
}) {
  return expense.isTransfer
      ? showEditTransferSheet(context, expense, firstDate: firstDate)
      : showEditExpenseSheet(context, expense, firstDate: firstDate);
}

/// Edit sheet for a spend or income row.
Future<void> showEditExpenseSheet(
  BuildContext context,
  Expense expense, {
  DateTime? firstDate,
}) async {
  final first = firstDate ?? DateTime(2000);
  final descController = TextEditingController(text: expense.description);
  final amountController =
      TextEditingController(text: minorToEditString(expense.amount));
  final categoryController = TextEditingController(text: expense.category);
  String paymentMode = expense.paymentMode;
  DateTime selectedDate = expense.date;
  // The builders below shadow `context`; keep the caller's for the split.
  final callerContext = context;

  // Payment modes offered in the editor. A row can carry a value outside this
  // list (SMS-imported income is stored with an empty one), and a dropdown
  // whose value matches no item throws — so keep the row's own value selectable.
  const knownModes = ['Cash', 'Credit Card', 'Debit Card', 'UPI', 'Other'];
  final modes = [
    ...knownModes,
    if (!knownModes.contains(paymentMode)) paymentMode,
  ];

  // DisposeWithRoute disposes the controllers once the sheet has closed.
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return DisposeWithRoute(
        notifiers: [descController, amountController, categoryController],
        child: StatefulBuilder(builder: (context, setModalState) {
          return Padding(
            padding: bottomSheetPadding(context),
            // Scrollable so the form can still be reached (and Save tapped)
            // when the keyboard shrinks the available height.
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text('Edit Expense',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.call_split, size: 18),
                        label: const Text('Split'),
                        // Close this sheet with its own context, then run the
                        // split from the caller's: the sheet's context is
                        // unmounted by the time the split sheet returns, and
                        // the split used to be silently dropped.
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          splitTransaction(callerContext, expense);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  TextField(
                    controller: amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                  TextField(
                    controller: categoryController,
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: paymentMode,
                    decoration:
                        const InputDecoration(labelText: 'Payment Mode'),
                    items: [
                      for (final m in modes)
                        DropdownMenuItem(
                            value: m, child: Text(m.isEmpty ? 'None' : m)),
                    ],
                    onChanged: (v) =>
                        setModalState(() => paymentMode = v ?? paymentMode),
                  ),
                  Row(
                    children: [
                      Text('Date: ${formatDateWithDay(selectedDate)}'),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: first,
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setModalState(() => selectedDate = picked);
                          }
                        },
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: kSheetActionHeight,
                    child: FilledButton(
                      onPressed: () async {
                        // Say why nothing happened. Returning silently made
                        // Save look like a dead button.
                        final problem =
                            validateAmountField(amountController.text);
                        if (problem != null) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(problem)));
                          return;
                        }
                        final amount =
                            parseMinor(amountController.text.trim())!;
                        final updated = Expense(
                          id: expense.id,
                          description: descController.text.trim(),
                          amount: amount,
                          date: selectedDate,
                          category: categoryController.text.trim(),
                          paymentMode: paymentMode,
                          type: expense.type,
                          accountId: expense.accountId,
                          toAccountId: expense.toAccountId,
                          // Keep the import link, or the next SMS scan offers
                          // the edited row again as a new transaction.
                          sourceRef: expense.sourceRef,
                        );
                        final provider = context.read<ExpenseProvider>();
                        final accountProvider = context.read<AccountProvider>();
                        await provider.updateExpense(updated);
                        await accountProvider.refreshBalances();
                        if (!context.mounted) return;
                        Navigator.pop(context);
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      );
    },
  );
}

/// Edit sheet for a transfer between accounts.
Future<void> showEditTransferSheet(
  BuildContext context,
  Expense transfer, {
  DateTime? firstDate,
}) async {
  final first = firstDate ?? DateTime(2000);
  final accountProvider0 = context.read<AccountProvider>();
  final accounts = accountProvider0.accounts;
  final amountController =
      TextEditingController(text: minorToEditString(transfer.amount));
  final toAmountController =
      TextEditingController(text: minorToEditString(transfer.receivedAmount));
  final noteController = TextEditingController(text: transfer.description);
  int? fromId = transfer.accountId;
  int? toId = transfer.toAccountId;
  DateTime date = transfer.date;

  bool crossCurrency() {
    final from = accountProvider0.accountById(fromId);
    final to = accountProvider0.accountById(toId);
    return from != null && to != null && from.symbol != to.symbol;
  }

  // DisposeWithRoute disposes the controllers once the sheet has closed.
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DisposeWithRoute(
      notifiers: [amountController, toAmountController, noteController],
      child: StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: bottomSheetPadding(context),
          // Scrollable so the form can still be reached (and Save tapped)
          // when the keyboard shrinks the available height.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Edit Transfer',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  initialValue:
                      accounts.any((a) => a.id == fromId) ? fromId : null,
                  decoration: const InputDecoration(labelText: 'From account'),
                  items: accounts
                      .map((a) => DropdownMenuItem<int?>(
                          value: a.id, child: Text(a.name)))
                      .toList(),
                  onChanged: (v) => setSheet(() => fromId = v),
                ),
                DropdownButtonFormField<int?>(
                  initialValue: accounts.any((a) => a.id == toId) ? toId : null,
                  decoration: const InputDecoration(labelText: 'To account'),
                  items: accounts
                      .map((a) => DropdownMenuItem<int?>(
                          value: a.id, child: Text(a.name)))
                      .toList(),
                  onChanged: (v) => setSheet(() => toId = v),
                ),
                TextField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
                if (crossCurrency())
                  TextField(
                    controller: toAmountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText:
                          'Amount received (${accountProvider0.accountById(toId)!.symbol})',
                    ),
                  ),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
                Row(
                  children: [
                    Text('Date: ${formatDateWithDay(date)}'),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: first,
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) setSheet(() => date = picked);
                      },
                      child: const Text('Change'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: kSheetActionHeight,
                  child: FilledButton(
                    onPressed: () async {
                      // Each of these used to bail out silently, so Save did
                      // nothing and said nothing.
                      String? problem =
                          validateAmountField(amountController.text);
                      if (problem == null && (fromId == null || toId == null)) {
                        problem = 'Pick both accounts';
                      } else if (problem == null && fromId == toId) {
                        problem = 'Pick two different accounts';
                      } else if (problem == null && crossCurrency()) {
                        problem = validateAmountField(toAmountController.text);
                      }
                      if (problem != null) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(problem)));
                        return;
                      }
                      final amount = parseMinor(amountController.text.trim())!;
                      final toAmount = crossCurrency()
                          ? parseMinor(toAmountController.text.trim())
                          : null;
                      final updated = Expense(
                        id: transfer.id,
                        description: noteController.text.trim().isEmpty
                            ? 'Transfer'
                            : noteController.text.trim(),
                        amount: amount,
                        date: date,
                        category: 'Transfer',
                        paymentMode: 'Other',
                        type: DbConstants.txTransfer,
                        accountId: fromId,
                        toAccountId: toId,
                        toAmount: toAmount,
                        sourceRef: transfer.sourceRef,
                      );
                      final expenseProvider = context.read<ExpenseProvider>();
                      final accountProvider = context.read<AccountProvider>();
                      await expenseProvider.updateExpense(updated);
                      await accountProvider.refreshBalances();
                      if (!context.mounted) return;
                      Navigator.pop(context);
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Splits one transaction into several categorized parts that sum to it —
/// e.g. one card charge that was really groceries plus a gift. The parts
/// inherit the original's date, account, type, and (for an imported row) its
/// sourceRef, so balances and dedup are unaffected.
Future<void> splitTransaction(BuildContext context, Expense original) async {
  if (original.id == null) return;
  final parts = await showModalBottomSheet<List<Expense>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _SplitSheet(original: original),
  );
  if (parts == null || parts.isEmpty || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final provider = context.read<ExpenseProvider>();
  final accountProvider = context.read<AccountProvider>();
  try {
    await DBService().splitExpense(original.id!, parts);
    await provider.reloadLoadedYears();
    await accountProvider.refreshBalances();
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Split into ${parts.length} transactions.')),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
  }
}

/// Bottom sheet that divides one transaction into several categorized parts.
/// Save is only enabled once the parts sum exactly to the original amount, so
/// a split can never change the total that hit the account.
class _SplitSheet extends StatefulWidget {
  final Expense original;
  const _SplitSheet({required this.original});

  @override
  State<_SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends State<_SplitSheet> {
  late final List<_PartCtrl> _parts;

  @override
  void initState() {
    super.initState();
    // Start with the whole amount on the original category plus one empty part,
    // so the common "carve a piece off" split is one edit away.
    _parts = [
      _PartCtrl(
        amount: minorToEditString(widget.original.amount),
        category: widget.original.category,
      ),
      _PartCtrl(amount: '', category: ''),
    ];
  }

  @override
  void dispose() {
    for (final p in _parts) {
      p.dispose();
    }
    super.dispose();
  }

  int get _sum => _parts.fold<int>(
      0, (s, p) => s + (parseMinor(p.amount.text.trim()) ?? 0));

  int get _remaining => widget.original.amount - _sum;

  bool get _valid {
    if (_remaining != 0) return false;
    for (final p in _parts) {
      final amt = parseMinor(p.amount.text.trim());
      if (amt == null || amt <= 0) return false;
      if (p.category.text.trim().isEmpty) return false;
    }
    return true;
  }

  void _save() {
    final o = widget.original;
    final parts = <Expense>[
      for (final p in _parts)
        Expense(
          description: o.description,
          amount: parseMinor(p.amount.text.trim())!,
          date: o.date,
          category: p.category.text.trim(),
          paymentMode: o.paymentMode,
          type: o.type,
          accountId: o.accountId,
          toAccountId: o.toAccountId,
          // Keep the import link on every part so a rescan still treats the
          // message as handled.
          sourceRef: o.sourceRef,
        ),
    ];
    Navigator.pop(context, parts);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: bottomSheetPadding(context),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text('Split transaction',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                '${widget.original.description} · '
                '${formatMoney(widget.original.amount)}',
                style: TextStyle(color: mutedTextColor(context)),
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _parts.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _parts[i].category,
                        decoration: const InputDecoration(
                            labelText: 'Category', isDense: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _parts[i].amount,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Amount', isDense: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: 'Remove part',
                      onPressed: _parts.length <= 2
                          ? null
                          : () => setState(() => _parts.removeAt(i).dispose()),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add part'),
                  onPressed: () => setState(
                      () => _parts.add(_PartCtrl(amount: '', category: ''))),
                ),
                const Spacer(),
                Text(
                  _remaining == 0
                      ? 'Balanced'
                      : 'Remaining ${formatMoneySigned(_remaining)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _remaining == 0
                        ? incomeColor(context)
                        : expenseColor(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: kSheetActionHeight,
              child: FilledButton(
                onPressed: _valid ? _save : null,
                child: const Text('Save split'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the split sheet: a category and an amount.
class _PartCtrl {
  final TextEditingController amount;
  final TextEditingController category;
  _PartCtrl({required String amount, required String category})
      : amount = TextEditingController(text: amount),
        category = TextEditingController(text: category);

  void dispose() {
    amount.dispose();
    category.dispose();
  }
}
