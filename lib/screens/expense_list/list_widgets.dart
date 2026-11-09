part of '../expense_list_screen.dart';

/// Totals for whatever the current filters show, leading the list so the
/// period's spend is visible without leaving the Transactions tab.
class _PeriodSummary extends StatelessWidget {
  final int count;
  final int spent;
  final int income;

  const _PeriodSummary({
    required this.count,
    required this.spent,
    required this.income,
  });

  @override
  Widget build(BuildContext context) {
    final muted = mutedTextColor(context);
    Widget figure(String label, int amount, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600,
                      color: muted)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(formatMoney(amount),
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ),
            ],
          ),
        );
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            figure('Spent', spent, expenseColor(context)),
            figure('Income', income, incomeColor(context)),
            Text('$count ${count == 1 ? 'entry' : 'entries'}',
                style: TextStyle(fontSize: 12, color: muted)),
          ],
        ),
      ),
    );
  }
}

/// Date heading over one day's transactions, with that day's spend.
class _DayHeader extends StatelessWidget {
  final DateTime day;
  final int spent;

  const _DayHeader({required this.day, required this.spent});

  String _label() {
    final today = DateUtils.dateOnly(DateTime.now());
    if (day == today) return 'Today';
    // Calendar arithmetic, not a 24h Duration, so a DST change doesn't lose
    // the "Yesterday" label for a day.
    if (day == DateTime(today.year, today.month, today.day - 1)) {
      return 'Yesterday';
    }
    return formatDateWithDay(day);
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: mutedTextColor(context),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          Expanded(child: Text(_label(), style: style)),
          if (spent > 0) Text('-${formatMoney(spent)}', style: style),
        ],
      ),
    );
  }
}

/// Leading avatar for a transaction row: a category icon on the category's
/// colour for spends, keeping the green/blue-grey semantics for income and
/// transfers.
class _CategoryAvatar extends StatelessWidget {
  final Expense expense;
  const _CategoryAvatar({required this.expense});

  @override
  Widget build(BuildContext context) {
    if (expense.isTransfer) {
      return CircleAvatar(
        backgroundColor: transferAvatarColor(context),
        child: Icon(Icons.swap_horiz, color: transferColor(context)),
      );
    }
    if (expense.isIncome) {
      return CircleAvatar(
        backgroundColor: incomeAvatarColor(context),
        child:
            Icon(categoryIcon(expense.category), color: incomeColor(context)),
      );
    }
    return CategoryAvatar(category: expense.category);
  }
}

/// A short vertical rule separating the period chip from the type chips in the
/// transactions toolbar.
class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 1,
        height: 24,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

/// An investment paid from (or back into) the filtered account. Tapping it
/// opens its type, where it can be edited like any other contribution.
class _InvestmentRow extends StatelessWidget {
  final Investment investment;
  const _InvestmentRow({required this.investment});

  @override
  Widget build(BuildContext context) {
    final i = investment;
    // Money out of the account for a contribution, back in for a withdrawal.
    final amount = i.isWithdrawal
        ? '+${formatMoney(-i.amount)}'
        : '-${formatMoney(i.amount)}';
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: incomeAvatarColor(context),
          child: Icon(Icons.trending_up, color: incomeColor(context)),
        ),
        title: Text(i.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${i.isWithdrawal ? 'Investment withdrawal' : 'Investment'}'
            ' · ${i.type}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        trailing: Text(amount,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: i.isWithdrawal
                    ? incomeColor(context)
                    : expenseColor(context))),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => InvestmentTypeScreen(type: i.type)),
        ),
      ),
    );
  }
}

/// Asks which category to file the selected rows under: an existing one from
/// the chips, or a new name typed in.
class _CategoryPickerDialog extends StatefulWidget {
  final int count;
  final List<String> suggestions;
  const _CategoryPickerDialog({required this.count, required this.suggestions});

  @override
  State<_CategoryPickerDialog> createState() => _CategoryPickerDialogState();
}

class _CategoryPickerDialogState extends State<_CategoryPickerDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typed = _controller.text.trim();
    return AlertDialog(
      title: Text('Move ${widget.count} to'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Category'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final c in widget.suggestions)
                  ChoiceChip(
                    label: Text(c),
                    selected: c.toLowerCase() == typed.toLowerCase(),
                    onSelected: (_) => setState(() => _controller.text = c),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: typed.isEmpty
              ? null
              : () {
                  // Reuse an existing spelling rather than start a near-twin.
                  final match = widget.suggestions.firstWhere(
                      (c) => c.toLowerCase() == typed.toLowerCase(),
                      orElse: () => typed);
                  Navigator.pop(context, match);
                },
          child: const Text('Move'),
        ),
      ],
    );
  }
}
