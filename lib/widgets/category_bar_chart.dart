import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/category_colors.dart';
import '../utils/category_icons.dart';
import '../utils/currency_format.dart';

/// Spending by category as a sorted horizontal bar list.
///
/// Replaces the old pie + separate breakdown list: a bar per category, longest
/// first, each labelled with its amount and share of the total and coloured by
/// [CategoryColors]. Bars read faster than pie slices when comparing many
/// categories, and folding the values into the bars removes the duplicate list
/// that used to sit under the chart.
///
/// Takes pre-computed [totals] (category to base-currency minor units) rather
/// than raw transactions — amounts are stored per source-account currency, so
/// the provider converts them to base currency before they reach here.
///
/// When [onCategoryTap] is given, tapping a row reports the category so the
/// caller can show that category's transactions. The widget sizes to its
/// content (one row per category), so it belongs inside a scroll view rather
/// than a fixed-height box.
class CategoryBarChart extends StatelessWidget {
  final Map<String, int> totals;
  final ValueChanged<String>? onCategoryTap;

  const CategoryBarChart({super.key, required this.totals, this.onCategoryTap});

  @override
  Widget build(BuildContext context) {
    final entries = totals.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final grand = entries.fold<int>(0, (s, e) => s + e.value);
    if (entries.isEmpty || grand == 0) {
      return const SizedBox.shrink();
    }
    final max = entries.first.value;

    final summary =
        entries.map((e) => '${e.key} ${formatMoney(e.value)}').join(', ');
    final tappable = onCategoryTap != null;

    return Semantics(
      label: 'Spending by category: $summary'
          '${tappable ? '. Tap a category for its transactions.' : ''}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final e in entries)
              _CategoryBar(
                label: e.key,
                amount: e.value,
                fraction: e.value / max,
                share: e.value / grand,
                color: CategoryColors.forCategory(e.key),
                onTap: tappable ? () => onCategoryTap!(e.key) : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  final String label;
  final int amount;

  /// Bar length relative to the largest category (0..1).
  final double fraction;

  /// Share of the grand total, shown as a percentage (0..1).
  final double share;
  final Color color;
  final VoidCallback? onTap;

  const _CategoryBar({
    required this.label,
    required this.amount,
    required this.fraction,
    required this.share,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.surfaceContainerHighest;
    final percent = (share * 100).toStringAsFixed(share >= 0.1 ? 0 : 1);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(categoryIcon(label), size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 8),
                Text('$percent%',
                    style: TextStyle(
                        color: mutedTextColor(context), fontSize: 12)),
                const SizedBox(width: 10),
                Text(formatMoney(amount),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: track),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: fraction.clamp(0.02, 1.0),
                        heightFactor: 1,
                        // A gradient along the bar (bright to deep) gives the
                        // fill some depth instead of a flat block of color.
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Color.lerp(color, Colors.white, 0.28) ?? color,
                                color,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
