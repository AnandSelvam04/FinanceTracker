import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/investment.dart';
import '../providers/investment_provider.dart';
import '../utils/currency_format.dart';
import 'add_investment_screen.dart';

/// Shows every contribution for a single investment [type], with the running
/// total and a month-by-month breakdown ("how much did I put into Silver in
/// each month/year"). Adding here appends a new contribution instead of
/// forcing the user to edit an existing one.
class InvestmentTypeScreen extends StatelessWidget {
  final String type;

  const InvestmentTypeScreen({super.key, required this.type});

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _monthLabel(String ym) {
    // ym is "YYYY-MM".
    final parts = ym.split('-');
    final year = parts[0];
    final month = int.tryParse(parts[1]) ?? 1;
    return '${_monthNames[(month - 1).clamp(0, 11)]} $year';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(type)),
      body: Consumer<InvestmentProvider>(
        builder: (context, provider, _) {
          final breakdown = provider.monthlyBreakdown(type);
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

          final months = breakdown.keys.toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total in $type',
                            style: const TextStyle(fontSize: 16)),
                        Text(
                          formatMoney(total),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                  itemCount: months.length,
                  itemBuilder: (context, index) {
                    final ym = months[index];
                    final monthItems = breakdown[ym]!;
                    final monthTotal =
                        monthItems.fold<int>(0, (sum, i) => sum + i.amount);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _monthLabel(ym),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                ),
                              ),
                              Text(
                                formatMoney(monthTotal),
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        ...monthItems.map((i) => _contributionTile(context, i)),
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
    return Dismissible(
      key: ValueKey(investment.id ?? '${investment.name}-${investment.date}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: Colors.red.shade400,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(context, investment),
      child: Card(
        elevation: 1,
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.green.shade100,
            child: const Icon(Icons.trending_up, color: Colors.green),
          ),
          title: Text(investment.name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle:
              Text(AppLocalizations.of(context).dateWithDay(investment.date)),
          trailing: Text(formatMoney(investment.amount),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          onTap: () => _editInvestment(context, investment),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(
      BuildContext context, Investment investment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete contribution?'),
        content: Text(
            'Remove "${investment.name}" for ${formatMoney(investment.amount)}?'),
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

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Edit Investment',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setModalState(() => type = v ?? type),
                ),
                if (type == Investment.otherType)
                  TextField(
                    controller: customTypeController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Enter investment type'),
                  ),
                Row(
                  children: [
                    Text(
                        'Date: ${AppLocalizations.of(context).dateWithDay(selectedDate)}'),
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
                  child: ElevatedButton(
                    onPressed: () async {
                      final amount = parseMinor(amountController.text.trim());
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
          );
        });
      },
    );
  }
}
