import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/investment_provider.dart';
import '../utils/currency_format.dart';
import '../utils/insets.dart';
import 'add_investment_screen.dart';
import 'investment_type_screen.dart';

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
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.investments)),
      body: Consumer<InvestmentProvider>(
        builder: (context, provider, _) {
          final all = provider.investments;

          if (all.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.trending_up, size: 48, color: Colors.grey),
                  const SizedBox(height: 8),
                  Text(l.noInvestments),
                ],
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
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l.totalInvested,
                            style: const TextStyle(fontSize: 16)),
                        Text(
                          formatMoney(provider.totalInvested),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
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
                      elevation: 2,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.green.shade100,
                          child: const Icon(Icons.trending_up,
                              color: Colors.green),
                        ),
                        title: Text(type,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${l.contributions(count)} · ${l.latest} ${l.dateWithDay(latest)}',
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(formatMoney(entry.value),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const Icon(Icons.chevron_right,
                                size: 18, color: Colors.grey),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  InvestmentTypeScreen(type: type),
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
        tooltip: l.addInvestment,
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
