import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../utils/category_colors.dart';
import '../utils/category_icons.dart';
import '../utils/insets.dart';
import '../widgets/section_header.dart';
import '../widgets/category_trend_chart.dart';
import '../widgets/empty_state.dart';
import '../widgets/category_avatar.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/dimens.dart';

class CategoryTrendsScreen extends StatefulWidget {
  const CategoryTrendsScreen({super.key});

  @override
  State<CategoryTrendsScreen> createState() => _CategoryTrendsScreenState();
}

class _CategoryTrendsScreenState extends State<CategoryTrendsScreen> {
  final Set<String> _selected = {};
  bool _initialized = false;

  /// How many months back the chart looks.
  int _span = 12;

  static const _spans = [6, 12, 24];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Loads every year the span reaches into.
  void _load() {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month - (_span - 1));
    unawaited(context
        .read<ExpenseProvider>()
        .ensureYearsLoaded([for (var y = first.year; y <= now.year; y++) y]));
  }

  /// Each category's spending over the span, biggest first — so the chart
  /// opens on where most of the money went, not on whichever three come
  /// first alphabetically.
  Map<String, int> _totals(ExpenseProvider provider) {
    final now = DateTime.now();
    final totals = <String, int>{};
    for (int i = _span - 1; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      provider
          .categoryTotalsForMonth(month.year, month.month)
          .forEach((c, v) => totals[c] = (totals[c] ?? 0) + v);
    }
    final order = totals.keys.toList()
      ..sort((a, b) {
        final bySpend = totals[b]!.compareTo(totals[a]!);
        return bySpend != 0 ? bySpend : a.compareTo(b);
      });
    return {for (final c in order) c: totals[c]!};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Category trends')),
      body: Consumer<ExpenseProvider>(
        builder: (context, provider, _) {
          final totals = _totals(provider);
          final categories = totals.keys.toList();
          if (!_initialized && categories.isNotEmpty) {
            _selected.addAll(categories.take(3));
            _initialized = true;
          }

          if (categories.isEmpty) {
            return EmptyState(
              icon: Icons.show_chart,
              title: 'Nothing to chart yet',
              message: 'No expenses recorded in the last $_span months.',
            );
          }

          final muted = mutedTextColor(context);
          return SingleChildScrollView(
            padding: scrollPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      for (final s in _spans)
                        ButtonSegment(value: s, label: Text('$s months')),
                    ],
                    selected: {_span},
                    onSelectionChanged: (v) {
                      setState(() => _span = v.first);
                      _load();
                    },
                  ),
                ),
                const SizedBox(height: Space.lg),
                SectionHeader('Spending by category (last $_span months)'),
                const SizedBox(height: Space.sm),
                CategoryTrendChart(
                  provider: provider,
                  categories: _selected.toList(),
                  months: _span,
                ),
                const SizedBox(height: Space.lg),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: categories.map((category) {
                    final selected = _selected.contains(category);
                    return FilterChip(
                      label: Text(category),
                      selected: selected,
                      showCheckmark: false,
                      avatar: Icon(categoryIcon(category),
                          size: 18,
                          color: CategoryColors.foreground(
                              CategoryColors.forCategory(category),
                              Theme.of(context).brightness)),
                      onSelected: (value) {
                        setState(() {
                          if (value) {
                            _selected.add(category);
                          } else {
                            _selected.remove(category);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                if (_selected.isNotEmpty) ...[
                  const SizedBox(height: Space.lg),
                  const SectionHeader('Totals'),
                  const SizedBox(height: Space.xs),
                  // The numbers behind the lines: the chart has no axis.
                  Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final c in categories)
                          if (_selected.contains(c))
                            ListTile(
                              dense: true,
                              leading: CategoryAvatar(category: c, radius: 16),
                              title: Text(c),
                              subtitle: Text(
                                  '${formatMoneyRounded(totals[c]! ~/ _span)} '
                                  'a month on average',
                                  style: TextStyle(color: muted)),
                              trailing: Text(formatMoneyRounded(totals[c]!),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
