import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/investment.dart';
import '../providers/investment_provider.dart';
import '../utils/currency_format.dart';
import '../utils/insets.dart';
import 'add_investment_screen.dart';

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
  String _periodLabel(AppLocalizations l, String key) {
    switch (_period) {
      case InvestmentPeriod.weekly:
        return l.weekOf(key);
      case InvestmentPeriod.monthly:
        final parts = key.split('-');
        final month = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 1;
        return '${l.monthName(month.clamp(1, 12))} ${parts[0]}';
      case InvestmentPeriod.yearly:
        return key;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l.totalInType(type),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<InvestmentPeriod>(
                    segments: [
                      ButtonSegment(
                          value: InvestmentPeriod.weekly,
                          label: Text(l.freqWeekly)),
                      ButtonSegment(
                          value: InvestmentPeriod.monthly,
                          label: Text(l.freqMonthly)),
                      ButtonSegment(
                          value: InvestmentPeriod.yearly,
                          label: Text(l.freqYearly)),
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
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _periodLabel(l, ym),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                ),
                              ),
                              Text(
                                formatMoney(periodTotal),
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
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
        tooltip: l.addToType(type),
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
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.deleteContribution),
        content: Text(l.deleteContributionBody(
            investment.name, formatMoney(investment.amount))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel)),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.delete)),
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
        final l = AppLocalizations.of(context);
        return StatefulBuilder(builder: (context, setModalState) {
          return Padding(
            padding: bottomSheetPadding(context),
            // Scrollable so the form can still be reached (and Save tapped)
            // when the keyboard shrinks the available height.
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.editInvestment,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(labelText: l.accountName),
                  ),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: l.amount),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: InputDecoration(labelText: l.accountType),
                    items: types
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setModalState(() => type = v ?? type),
                  ),
                  if (type == Investment.otherType)
                    TextField(
                      controller: customTypeController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                          labelText: l.enterInvestmentType),
                    ),
                  Row(
                    children: [
                      Text('${l.date}: ${l.dateWithDay(selectedDate)}'),
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
                        child: Text(l.change),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: kSheetActionHeight,
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
                      child: Text(l.save),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }
}
