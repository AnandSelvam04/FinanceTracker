import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/investment_provider.dart';
import '../utils/app_colors.dart';
import '../utils/category_colors.dart';
import '../utils/currency_format.dart';
import '../utils/insets.dart';
import '../widgets/empty_state.dart';
import '../widgets/hero_total_card.dart';
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

          // Share of the total per type, for the allocation bar and each row.
          // Only positive holdings count: a type netted below zero by
          // withdrawals has no slice of the portfolio.
          final positiveTotal = totalsByType.fold<int>(
              0, (sum, e) => sum + (e.value > 0 ? e.value : 0));
          final contributions = all.length;

          return RefreshIndicator(
            onRefresh: provider.fetchInvestments,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              // One extra leading item for the hero card, so it scrolls with
              // the list instead of pinning a third of a small screen.
              itemCount: totalsByType.length + 1,
              separatorBuilder: (_, index) =>
                  SizedBox(height: index == 0 ? 16 : 8),
              padding: scrollPadding(context, all: 12, fab: true),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return HeroTotalCard(
                    label: 'Total invested',
                    amount: formatMoneySigned(provider.totalInvested),
                    caption: '${totalsByType.length} '
                        '${totalsByType.length == 1 ? 'type' : 'types'} · '
                        '$contributions '
                        '${contributions == 1 ? 'contribution' : 'contributions'}',
                    footer: positiveTotal > 0 && totalsByType.length > 1
                        ? _AllocationBar(
                            totals: totalsByType, total: positiveTotal)
                        : null,
                  );
                }
                final entry = totalsByType[index - 1];
                final type = entry.key;
                final items = provider.ofType(type);
                // Fetch order is newest-first, so the first item is latest.
                final latest = items.first.date;
                final count = items.length;
                final share = positiveTotal > 0 && entry.value > 0
                    ? (entry.value * 100 / positiveTotal).round()
                    : null;
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    // Same colour as this type's slice of the allocation bar.
                    leading: Builder(builder: (context) {
                      final c = _typeColor(index - 1);
                      final dark =
                          Theme.of(context).brightness == Brightness.dark;
                      return CircleAvatar(
                        backgroundColor:
                            c.withValues(alpha: dark ? 0.28 : 0.15),
                        child: Icon(Icons.trending_up, color: c),
                      );
                    }),
                    title: Text(type,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '$count ${count == 1 ? 'contribution' : 'contributions'}'
                      ' · latest ${_compactDate(latest)}',
                    ),
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(formatMoneySigned(entry.value),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        if (share != null)
                          Text('$share%',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: mutedTextColor(context))),
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

/// Colour for the type at [rank] in the largest-first list. Assigned by
/// position rather than hashed from the name: hashing gave unrelated types
/// (e.g. Gold and FD) the same colour, which made their slices of the
/// allocation bar indistinguishable.
Color _typeColor(int rank) =>
    CategoryColors.palette[rank % CategoryColors.palette.length];

/// "25 Sep" this year, "25 Sep 2025" otherwise — short enough that a row's
/// subtitle stays on one line.
String _compactDate(DateTime d) => d.year == DateTime.now().year
    ? '${d.day} ${monthName(d.month).substring(0, 3)}'
    : formatShortDate(d);

/// A single stacked bar splitting the portfolio by type, each segment in the
/// type's colour (the same colour as its row avatar below).
/// [totals] is the full largest-first list, so ranks match the rows.
class _AllocationBar extends StatelessWidget {
  final List<MapEntry<String, int>> totals;
  final int total;

  const _AllocationBar({required this.totals, required this.total});

  @override
  Widget build(BuildContext context) {
    final slices = totals.where((e) => e.value > 0).toList();
    return Semantics(
      label: 'Allocation: ${slices.map((e) => '${e.key} '
          '${(e.value * 100 / total).round()}%').join(', ')}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 10,
          child: Row(
            children: [
              for (var i = 0; i < slices.length; i++)
                Expanded(
                  // Flex needs an int; per-mille keeps small slices visible
                  // without overflowing on very large totals.
                  flex: (slices[i].value * 1000 / total).round().clamp(1, 1000),
                  child: Container(
                    margin:
                        EdgeInsets.only(right: i == slices.length - 1 ? 0 : 2),
                    color: _typeColor(totals.indexOf(slices[i])),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
