import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/investment.dart';
import '../providers/investment_provider.dart';
import '../utils/currency_format.dart';
import 'add_investment_screen.dart';

class InvestmentsScreen extends StatefulWidget {
  const InvestmentsScreen({super.key});

  @override
  State<InvestmentsScreen> createState() => _InvestmentsScreenState();
}

class _InvestmentsScreenState extends State<InvestmentsScreen> {
  String? _typeFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<InvestmentProvider>();
      if (provider.investments.isEmpty) {
        provider.fetchInvestments();
      }
    });
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<bool> _confirmDelete(Investment investment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete investment?'),
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

  Future<void> _editInvestment(Investment investment) async {
    final nameController = TextEditingController(text: investment.name);
    final amountController =
        TextEditingController(text: minorToEditString(investment.amount));
    String type = investment.type;
    DateTime selectedDate = investment.date;

    const types = [
      'Stocks',
      'Mutual Funds',
      'Bonds',
      'FD',
      'Gold',
      'Silver',
      'Other'
    ];
    if (!types.contains(type)) type = 'Other';

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
                Row(
                  children: [
                    Text('Date: ${_formatDate(selectedDate)}'),
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
                      final amount =
                          parseMinor(amountController.text.trim());
                      if (amount == null) return;
                      final updated = Investment(
                        id: investment.id,
                        name: nameController.text.trim(),
                        amount: amount,
                        date: selectedDate,
                        type: type,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Investments')),
      body: Consumer<InvestmentProvider>(
        builder: (context, provider, _) {
          final all = provider.investments;
          final types = all.map((i) => i.type).toSet().toList()..sort();
          final investments = _typeFilter == null
              ? all
              : all.where((i) => i.type == _typeFilter).toList();
          final total =
              investments.fold<int>(0, (sum, i) => sum + i.amount);

          if (all.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.trending_up, size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('No investments yet. Add one to start tracking.'),
                ],
              ),
            );
          }

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
                        Text(
                          _typeFilter == null
                              ? 'Total Invested'
                              : 'Total ($_typeFilter)',
                          style: const TextStyle(fontSize: 16),
                        ),
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
              if (types.length > 1)
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: const Text('All'),
                          selected: _typeFilter == null,
                          onSelected: (_) =>
                              setState(() => _typeFilter = null),
                        ),
                      ),
                      ...types.map((t) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(t),
                              selected: _typeFilter == t,
                              onSelected: (_) =>
                                  setState(() => _typeFilter = t),
                            ),
                          )),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  itemCount: investments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  padding: const EdgeInsets.all(12),
                  itemBuilder: (context, index) {
                    final investment = investments[index];
                    return Dismissible(
                      key: ValueKey(
                          investment.id ?? '${investment.name}-$index'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        color: Colors.red.shade400,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (_) => _confirmDelete(investment),
                      child: Card(
                        elevation: 2,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green.shade100,
                            child: const Icon(Icons.trending_up,
                                color: Colors.green),
                          ),
                          title: Text(investment.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${investment.type} · ${_formatDate(investment.date)}'),
                          trailing: Text(
                              formatMoney(investment.amount),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          onTap: () => _editInvestment(investment),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add investment',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddInvestmentScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
