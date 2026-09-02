import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:provider/provider.dart';
import '../models/investment.dart';
import '../utils/app_colors.dart';
import '../providers/investment_provider.dart';
import '../utils/currency_format.dart';
import '../utils/insets.dart';
import 'add_investment_screen.dart';
import '../utils/date_format.dart';

/// Shows every contribution for a single investment [type], with the running
/// total and a breakdown that can be grouped by week, month, or year ("how
/// much did I put into Silver in each period"). Adding here appends a new
/// contribution instead of forcing the user to edit an existing one.
class InvestmentTypeScreen extends StatefulWidget {
  final String type;

  const InvestmentTypeScreen({super.key, required this.type});

  @override
  State<InvestmentTypeScreen> createState() => _InvestmentTypeScreenState();
}

class _InvestmentTypeScreenState extends State<InvestmentTypeScreen> {
  InvestmentPeriod _period = InvestmentPeriod.monthly;

  String get type => widget.type;

  /// Human label for a period bucket key, formatted for the active grouping.
  String _periodLabel(String key) {
    switch (_period) {
      case InvestmentPeriod.weekly:
        return 'Week of $key';
      case InvestmentPeriod.monthly:
        final parts = key.split('-');
        final month = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 1;
        return '${monthName(month.clamp(1, 12))} ${parts[0]}';
      case InvestmentPeriod.yearly:
        return key;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(type)),
      body: Consumer<InvestmentProvider>(
        builder: (context, provider, _) {
          final breakdown = provider.breakdownByPeriod(type, _period);
          final entries = provider.ofType(type);
          final total = entries.fold<int>(0, (sum, i) => sum + i.amount);

          // When the last contribution of this type is deleted, drop back to
          // the list — an empty type page has nothing to show.
          if (entries.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) Navigator.of(context).maybePop();
            });
            return const SizedBox.shrink();
          }

          final periods = breakdown.keys.toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Card(
                  margin: EdgeInsets.zero,
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total in $type',
                            style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer)),
                        Text(
                          formatMoney(total),
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<InvestmentPeriod>(
                    segments: [
                      ButtonSegment(
                          value: InvestmentPeriod.weekly,
                          label: const Text('Weekly')),
                      ButtonSegment(
                          value: InvestmentPeriod.monthly,
                          label: const Text('Monthly')),
                      ButtonSegment(
                          value: InvestmentPeriod.yearly,
                          label: const Text('Yearly')),
                    ],
                    selected: {_period},
                    onSelectionChanged: (s) =>
                        setState(() => _period = s.first),
                    showSelectedIcon: false,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: ListView.builder(
                  padding: scrollPadding(context, all: 12, top: 0, fab: true),
                  itemCount: periods.length,
                  itemBuilder: (context, index) {
                    final ym = periods[index];
                    final periodItems = breakdown[ym]!;
                    final periodTotal =
                        periodItems.fold<int>(0, (sum, i) => sum + i.amount);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _periodLabel(ym),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              Text(
                                formatMoney(periodTotal),
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        ...periodItems
                            .map((i) => _contributionTile(context, i)),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add to $type',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddInvestmentScreen(initialType: type),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _contributionTile(BuildContext context, Investment investment) {
    // A Dismissible exposes no action to TalkBack or switch access, so swipe
    // was the only way to delete a contribution. Add a custom semantics
    // action and a long-press alongside it.
    return Semantics(
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Delete'): () =>
              _confirmDelete(context, investment),
        },
        child: Dismissible(
          key: ValueKey(
              investment.id ?? '${investment.name}-${investment.date}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: Colors.red.shade400,
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          confirmDismiss: (_) => _confirmDelete(context, investment),
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: incomeAvatarColor(context),
                child: Icon(Icons.trending_up, color: incomeColor(context)),
              ),
              title: Text(investment.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(formatDateWithDay(investment.date)),
              trailing: Text(formatMoney(investment.amount),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => _editInvestment(context, investment),
              onLongPress: () => _confirmDelete(context, investment),
            ),
          ),
        ));
  }

  Future<bool> _confirmDelete(
      BuildContext context, Investment investment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete contribution?'),
        content: Text('Remove "${investment.name}" for '
            '${formatMoney(investment.amount)}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      // ignore: use_build_context_synchronously
      await context.read<InvestmentProvider>().deleteInvestment(investment.id!);
      return true;
    }
    return false;
  }

  Future<void> _editInvestment(
      BuildContext context, Investment investment) async {
    final nameController = TextEditingController(text: investment.name);
    final amountController =
        TextEditingController(text: minorToEditString(investment.amount));
    DateTime selectedDate = investment.date;

    const types = Investment.builtInTypes;
    final isBuiltIn = types.contains(investment.type);
    String type = isBuiltIn ? investment.type : Investment.otherType;
    final customTypeController =
        TextEditingController(text: isBuiltIn ? '' : investment.type);

    // The sheet owns these controllers for its lifetime; dispose them once
    // it closes rather than leaking one set per open/close cycle.
    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return StatefulBuilder(builder: (context, setModalState) {
            return Padding(
              padding: bottomSheetPadding(context),
              // Scrollable so the form can still be reached (and Save tapped)
              // when the keyboard shrinks the available height.
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Edit Investment',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Amount'),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: types
                          .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) => setModalState(() => type = v ?? type),
                    ),
                    if (type == Investment.otherType)
                      TextField(
                        controller: customTypeController,
                        textCapitalization: TextCapitalization.words,
                        decoration:
                            InputDecoration(labelText: 'Enter investment type'),
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
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
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
                      child: ElevatedButton(
                        onPressed: () async {
                          final amount =
                              parseMinor(amountController.text.trim());
                          if (amount == null) return;
                          final resolvedType = type == Investment.otherType
                              ? customTypeController.text.trim()
                              : type;
                          if (resolvedType.isEmpty) return;
                          final updated = Investment(
                            id: investment.id,
                            name: nameController.text.trim(),
                            amount: amount,
                            date: selectedDate,
                            type: resolvedType,
                          );
                          final provider = context.read<InvestmentProvider>();
                          await provider.updateInvestment(updated);
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
          });
        },
      );
    } finally {
      nameController.dispose();
      amountController.dispose();
      customTypeController.dispose();
    }
  }
}
