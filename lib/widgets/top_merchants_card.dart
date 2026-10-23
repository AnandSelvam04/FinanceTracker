import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/merchant_summary.dart';
import 'category_avatar.dart';
import 'section_header.dart';

/// Where the money went, by merchant rather than category. Tapping a merchant
/// lists the transactions behind its total.
class TopMerchantsCard extends StatelessWidget {
  final List<MerchantTotal> merchants;
  final int periodTotal;
  const TopMerchantsCard(
      {super.key, required this.merchants, required this.periodTotal});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Top merchants'),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (final m in merchants)
                ListTile(
                  leading: CategoryAvatar(category: m.rows.first.category),
                  title: Text(m.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${m.count} transaction${m.count == 1 ? '' : 's'}'
                    '${periodTotal > 0 ? ' · ${(m.total / periodTotal * 100).round()}% of spend' : ''}',
                    style:
                        TextStyle(fontSize: 12, color: mutedTextColor(context)),
                  ),
                  trailing: Text(formatMoney(m.total),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () => _showRows(context, m),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _showRows(BuildContext context, MerchantTotal m) {
    final baseAmountOf = context.read<ExpenseProvider>().baseAmountOf;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(m.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: Text(formatMoney(m.total),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in m.rows)
                      ListTile(
                        leading: CategoryAvatar(category: e.category),
                        title:
                            Text(e.category, overflow: TextOverflow.ellipsis),
                        subtitle: Text(formatDateWithDay(e.date)),
                        trailing: Text(formatMoney(baseAmountOf(e)),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
