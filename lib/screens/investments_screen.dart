import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/investment_provider.dart';
import '../utils/currency_format.dart';
import '../utils/insets.dart';
import '../widgets/empty_state.dart';
import 'add_investment_screen.dart';
import 'investment_type_screen.dart';
import '../utils/date_format.dart';

class InvestmentsScreen extends StatefulWidget {
  const InvestmentsScreen({super.key});

  @override
  State<InvestmentsScreen> createState() => _InvestmentsScreenState();
}

class _InvestmentsScreenState extends State<InvestmentsScreen> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Investments')),
      body: Consumer<InvestmentProvider>(
        builder: (context, provider, _) {
          final all = provider.investments;

          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.trending_up,
              title: 'No investments yet',
              message: 'Record a contribution to start tracking your holdings.',
              actionLabel: 'Add investment',
              onAction: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddInvestmentScreen()),
              ),
            );
          }

          // Each type is one bucket that auto-accumulates every contribution,
          // so adding to Silver never means editing the previous Silver entry.
          final totalsByType = provider.totalsByType();

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
                        Text('Total Invested',
                            style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer)),
                        Text(
                          formatMoney(provider.totalInvested),
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
              Expanded(
                child: ListView.separated(
                  itemCount: totalsByType.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  padding: scrollPadding(context, all: 12, fab: true),
                  itemBuilder: (context, index) {
                    final entry = totalsByType[index];
                    final type = entry.key;
                    final items = provider.ofType(type);
                    // Fetch order is newest-first, so the first item is latest.
                    final latest = items.first.date;
                    final count = items.length;
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.secondaryContainer,
                          child: Icon(Icons.trending_up,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer),
                        ),
                        title: Text(type,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '$count ${count == 1 ? 'contribution' : 'contributions'}'
                          ' · latest ${formatDateWithDay(latest)}',
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(formatMoney(entry.value),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Icon(Icons.chevron_right,
                                size: 18,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => InvestmentTypeScreen(type: type),
                            ),
                          );
                        },
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
        tooltip: 'Add Investment',
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
