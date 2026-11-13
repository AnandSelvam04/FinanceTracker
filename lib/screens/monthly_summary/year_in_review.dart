part of '../monthly_summary_screen.dart';

/// The year at a glance: spending month by month (tap a bar to open that
/// month) and the figures worth remembering about it.
class _YearInReview extends StatelessWidget {
  final YearReview review;
  final ValueChanged<int> onMonthTap;
  const _YearInReview({required this.review, required this.onMonthTap});

  @override
  Widget build(BuildContext context) {
    if (review.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final muted = mutedTextColor(context);
    final peak = review.monthlyExpense
        .fold<int>(0, (m, v) => v > m ? v : m)
        .clamp(1, 1 << 62);
    final highest = review.highestMonth;
    final lowest = review.lowestMonth;
    final bestSaving = review.bestSavingMonth;
    final biggest = review.biggest;

    Widget fact(IconData icon, String label, String value, {String? detail}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label),
                    if (detail != null)
                      Text(detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: FontSizes.caption, color: muted)),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Month by month'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.sm, Space.lg, Space.sm, Space.sm),
            child: SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var m = 1; m <= 12; m++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: '${monthName(m)}: '
                            '${formatMoney(review.monthlyExpense[m - 1])} '
                            'spent',
                        excludeSemantics: true,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(Radii.sm),
                          onTap: () => onMonthTap(m),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Flexible(
                                child: FractionallySizedBox(
                                  // A month with a net refund has nothing
                                  // to draw.
                                  heightFactor:
                                      (review.monthlyExpense[m - 1] / peak)
                                          .clamp(0.0, 1.0),
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: Space.xs),
                                    decoration: BoxDecoration(
                                      color: m == highest
                                          ? expenseColor(context)
                                          : scheme.primary,
                                      borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(Radii.xs)),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: Space.sm),
                              Text(monthName(m).substring(0, 1),
                                  style: TextStyle(
                                      fontSize: FontSizes.caption,
                                      color: muted)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.lg),
        const SectionHeader('Year in review'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: Space.lg, vertical: Space.sm),
            child: Column(
              children: [
                fact(Icons.functions, 'Average month',
                    formatMoney(review.averageMonthlyExpense)),
                if (highest != null)
                  fact(Icons.arrow_upward, 'Highest spending',
                      formatMoney(review.monthlyExpense[highest - 1]),
                      detail: monthName(highest)),
                if (lowest != null)
                  fact(Icons.arrow_downward, 'Lowest spending',
                      formatMoney(review.monthlyExpense[lowest - 1]),
                      detail: monthName(lowest)),
                if (bestSaving != null)
                  fact(
                      Icons.savings_outlined,
                      'Most saved',
                      formatMoneySigned(review.monthlyIncome[bestSaving - 1] -
                          review.monthlyExpense[bestSaving - 1]),
                      detail: monthName(bestSaving)),
                if (biggest != null)
                  fact(Icons.receipt_long_outlined, 'Biggest expense',
                      formatMoney(biggest.amount),
                      detail: '${biggest.description} · '
                          '${formatShortDate(biggest.date)}'),
                fact(Icons.event_available_outlined, 'No-spend days',
                    '${review.noSpendDays}'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
