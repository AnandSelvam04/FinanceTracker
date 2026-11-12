part of '../monthly_summary_screen.dart';

/// Week stepper mirroring [MonthSelector], showing the selected week's range.
class _WeekSelector extends StatelessWidget {
  final String heading;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _WeekSelector({
    required this.heading,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous week',
          onPressed: onPrev,
        ),
        Text(heading, style: const TextStyle(fontSize: FontSizes.body)),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next week',
          onPressed: onNext,
        ),
      ],
    );
  }
}

/// Dropdown that scopes the summary to a single category (or all of them).
class _CategoryFilter extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onChanged;
  const _CategoryFilter({
    super.key,
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      isExpanded: true,
      initialValue: selected,
      decoration: const InputDecoration(
        labelText: 'Category',
        prefixIcon: Icon(Icons.filter_list),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('All Categories'),
        ),
        ...categories.map((c) => DropdownMenuItem<String?>(
              value: c,
              child: Text(c, overflow: TextOverflow.ellipsis),
            )),
      ],
      onChanged: onChanged,
    );
  }
}

/// One category row with a share-of-spend progress bar, a percentage, and the
/// month-over-month delta. Tapping it drills into that category's transactions.
class _CategoryProgressRow extends StatelessWidget {
  final String category;
  final int amount;
  final int previous;
  final int total;
  final VoidCallback onTap;
  const _CategoryProgressRow({
    required this.category,
    required this.amount,
    required this.previous,
    required this.total,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = CategoryColors.forCategory(category);
    final fraction = total > 0 ? (amount / total).clamp(0.0, 1.0) : 0.0;
    final pct = total > 0 ? (amount / total * 100).round() : 0;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            vertical: Space.sm, horizontal: Space.xs),
        child: Row(
          children: [
            CategoryAvatar(category: category, radius: 18),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(category,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text(formatMoney(amount),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  LinearProgressIndicator(
                    value: fraction,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                  const SizedBox(height: Space.xs),
                  Row(
                    children: [
                      Expanded(
                        child: Text('$pct% of spend',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: FontSizes.caption,
                                color: mutedTextColor(context))),
                      ),
                      _DeltaLabel(current: amount, previous: previous),
                    ],
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

/// The transactions behind one category for the selected period, shown when a
/// category is picked in the filter.
class _CategoryFocus extends StatelessWidget {
  final String category;
  final List<Expense> rows;
  final int total;
  final int previous;
  final int Function(Expense) baseAmountOf;
  const _CategoryFocus({
    required this.category,
    required this.rows,
    required this.total,
    required this.previous,
    required this.baseAmountOf,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Row(
              children: [
                CategoryAvatar(category: category, radius: 22),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(category,
                          style: Theme.of(context).textTheme.titleLarge,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: Space.xxs),
                      Text(
                        '${rows.length} transaction'
                        '${rows.length == 1 ? '' : 's'}',
                        style: TextStyle(
                            color: mutedTextColor(context),
                            fontSize: FontSizes.body),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatMoney(total),
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: Space.xxs),
                    _DeltaLabel(current: total, previous: previous),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.sm),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Space.sm),
            child: Text('No transactions in this category for the period.',
                style: TextStyle(color: mutedTextColor(context))),
          )
        else
          ...rows.map((e) => Card(
                child: ListTile(
                  leading: CategoryAvatar(category: category),
                  title: Text(
                      e.description.isEmpty
                          ? '(no description)'
                          : e.description,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(formatDateWithDay(e.date)),
                  trailing: Text(formatMoney(baseAmountOf(e)),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              )),
      ],
    );
  }
}

/// Shows the change against the comparison period with a direction arrow.
class _DeltaLabel extends StatelessWidget {
  final int current;
  final int previous;
  const _DeltaLabel({required this.current, required this.previous});

  @override
  Widget build(BuildContext context) {
    final delta = current - previous;
    if (previous == 0 && current == 0) {
      return const Text('—', style: TextStyle(fontSize: FontSizes.caption));
    }
    final up = delta > 0;
    final flat = delta == 0;
    final color = flat
        ? mutedTextColor(context)
        : up
            ? expenseColor(context)
            : incomeColor(context);
    final icon = flat
        ? Icons.remove
        : up
            ? Icons.arrow_upward
            : Icons.arrow_downward;
    final pct = previous > 0
        ? ' (${(delta.abs() / previous * 100).toStringAsFixed(0)}%)'
        : '';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        Text('${formatMoney(delta.abs())}$pct',
            style: TextStyle(fontSize: FontSizes.caption, color: color)),
      ],
    );
  }
}
