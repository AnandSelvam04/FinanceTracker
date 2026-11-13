part of '../home_screen.dart';

/// Headline spend with an animated count-up. Income is not repeated here:
/// the summary cards directly below already show it.
class _TotalHeadline extends StatelessWidget {
  final String label;
  final int amount;
  const _TotalHeadline({
    required this.label,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: FontSizes.caption,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
            color: mutedTextColor(context),
          ),
        ),
        const SizedBox(height: Space.xxs),
        // ShaderMask paints the count-up total with the brand gradient. The
        // white base color is what the srcIn blend replaces with the gradient.
        ShaderMask(
          shaderCallback: (bounds) =>
              brandGradient(context).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: AnimatedMoney(
            value: amount,
            format: formatMoney,
            style: const TextStyle(
              fontSize: FontSizes.display,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

/// Income and Expenses shown side by side as two summary cards under the
/// headline total — the at-a-glance split the attached designs lead with.
class _SummaryPills extends StatelessWidget {
  final int income;
  final int expense;
  const _SummaryPills({required this.income, required this.expense});

  @override
  Widget build(BuildContext context) {
    // The headline above is already the period's spend, so the second card
    // shows what is left after it (income minus spend) rather than repeating
    // the same figure.
    final net = income - expense;
    return Row(
      children: [
        Expanded(
          child: _SummaryPill(
            label: 'Income',
            amount: income,
            icon: Icons.south_west,
            color: incomeColor(context),
          ),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: _SummaryPill(
            label: net < 0 ? 'Overspent' : 'Saved',
            amount: net.abs(),
            icon: net < 0 ? Icons.trending_down : Icons.savings_outlined,
            color: net < 0 ? expenseColor(context) : incomeColor(context),
          ),
        ),
      ],
    );
  }
}

/// A single labelled amount card with a colored icon badge.
class _SummaryPill extends StatelessWidget {
  final String label;
  final int amount;
  final IconData icon;
  final Color color;
  const _SummaryPill({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Space.md, vertical: Space.md),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(Space.sm),
              decoration: BoxDecoration(
                color: color.withValues(alpha: dark ? 0.24 : 0.14),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontSize: FontSizes.caption,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600,
                      color: mutedTextColor(context),
                    ),
                  ),
                  const SizedBox(height: Space.xxs),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatMoney(amount),
                      style: TextStyle(
                        fontSize: FontSizes.bodyLarge,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How much of the month's overall budget is used, as a ring beside what is
/// left (or how far over it is) — read at a glance, where the Budgets tab
/// takes a tap. Tapping it opens that tab. Renders nothing when no overall
/// budget is set for the month.
class _BudgetRing extends StatelessWidget {
  /// Overall cap and spend for the month, in base-currency minor units.
  final int cap;
  final int spent;
  final VoidCallback onTap;
  const _BudgetRing(
      {required this.cap, required this.spent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (cap <= 0) return const SizedBox.shrink();
    final left = cap - spent;
    final over = left < 0;
    final ratio = (spent / cap).clamp(0.0, 1.0).toDouble();
    final percent = (spent * 100 / cap).round();
    final color = over
        ? dangerColor(context)
        : percent >= 90
            ? warningColor(context)
            : incomeColor(context);
    // The ring gives the share away even with the figures masked.
    final hidden = CurrencyFormat.hideAmounts;
    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Haptics.tick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.md, Space.md, Space.sm, Space.md),
            child: Row(
              children: [
                Semantics(
                  label: hidden ? 'Budget used' : '$percent% of budget used',
                  excludeSemantics: true,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: hidden ? 0 : ratio),
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) =>
                              CircularProgressIndicator(
                            value: value,
                            strokeWidth: 6,
                            strokeCap: StrokeCap.round,
                            color: color,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                          ),
                        ),
                        Center(
                          child: Text(
                            hidden ? '••' : '$percent%',
                            // Sized to the ring, not to the text setting.
                            textScaler: TextScaler.noScaling,
                            style: const TextStyle(
                                fontSize: FontSizes.caption,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        over
                            ? 'Over budget by ${formatMoney(-left)}'
                            : '${formatMoney(left)} left to spend',
                        style: TextStyle(
                          fontSize: FontSizes.body,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: Space.xxs),
                      Text(
                        '${formatMoneyRounded(spent)} of '
                        '${formatMoneyRounded(cap)} budget',
                        style: TextStyle(
                            fontSize: FontSizes.caption,
                            color: mutedTextColor(context)),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: mutedTextColor(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A run of days without spending, shown once it is two or more: a small
/// reason to open the app and keep it going. Hidden otherwise.
class _StreakChip extends StatelessWidget {
  final int days;
  const _StreakChip({required this.days});

  @override
  Widget build(BuildContext context) {
    if (days < 2) return const SizedBox.shrink();
    final warn = warningColor(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Space.md, vertical: Space.sm),
        decoration: BoxDecoration(
          color: warn.withValues(alpha: dark ? 0.2 : 0.14),
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department, size: 18, color: warn),
            const SizedBox(width: Space.sm),
            Flexible(
              child: Text(
                '$days no-spend days in a row',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: FontSizes.body, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The month in plain words: what [dashboardInsights] found worth saying,
/// each line with an icon tinted by whether it is good news.
class _InsightsCard extends StatelessWidget {
  final List<Insight> insights;
  const _InsightsCard({required this.insights});

  static IconData _icon(InsightKind kind) => switch (kind) {
        InsightKind.budget => Icons.donut_large,
        InsightKind.category => Icons.category_outlined,
        InsightKind.total => Icons.compare_arrows,
        InsightKind.savings => Icons.savings_outlined,
        InsightKind.biggest => Icons.receipt_long_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: Column(
        children: [
          const SectionHeader('Insights'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.md, vertical: Space.sm),
              child: Column(
                children: [
                  for (final insight in insights)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      child: Row(
                        children: [
                          Builder(builder: (context) {
                            final color = switch (insight.tone) {
                              InsightTone.good => incomeColor(context),
                              InsightTone.warn => warningColor(context),
                              InsightTone.neutral => infoColor(context),
                            };
                            return Container(
                              padding: const EdgeInsets.all(Space.sm),
                              decoration: BoxDecoration(
                                color:
                                    color.withValues(alpha: dark ? 0.24 : 0.14),
                                borderRadius: BorderRadius.circular(Radii.md),
                              ),
                              child: Icon(_icon(insight.kind),
                                  size: 18, color: color),
                            );
                          }),
                          const SizedBox(width: Space.md),
                          Expanded(
                            child: Text(insight.text,
                                style:
                                    const TextStyle(fontSize: FontSizes.body)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
