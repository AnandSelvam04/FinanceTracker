import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/expense_provider.dart';
import '../utils/category_colors.dart';
import '../widgets/category_trend_chart.dart';

class CategoryTrendsScreen extends StatefulWidget {
  const CategoryTrendsScreen({super.key});

  @override
  State<CategoryTrendsScreen> createState() => _CategoryTrendsScreenState();
}

class _CategoryTrendsScreenState extends State<CategoryTrendsScreen> {
  final Set<String> _selected = {};
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ExpenseProvider>();
      final now = DateTime.now();
      // The 12-month window can span two calendar years.
      provider.ensureYearLoaded(now.year);
      provider.ensureYearLoaded(now.year - 1);
    });
  }

  List<String> _availableCategories(ExpenseProvider provider) {
    final now = DateTime.now();
    final categories = <String>{};
    for (int i = 11; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      categories.addAll(
          provider.categoryTotalsForMonth(month.year, month.month).keys);
    }
    final list = categories.toList()..sort();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.categoryTrends)),
      body: Consumer<ExpenseProvider>(
        builder: (context, provider, _) {
          final categories = _availableCategories(provider);

          // Preselect the top few categories on first load.
          if (!_initialized && categories.isNotEmpty) {
            _selected.addAll(categories.take(3));
            _initialized = true;
          }

          if (categories.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l.noExpenses12Months),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.spendingByCategory,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                CategoryTrendChart(
                  provider: provider,
                  categories: _selected.toList(),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: categories.map((category) {
                    final selected = _selected.contains(category);
                    return FilterChip(
                      label: Text(category),
                      selected: selected,
                      avatar: CircleAvatar(
                        backgroundColor: CategoryColors.forCategory(category),
                        radius: 8,
                      ),
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
              ],
            ),
          );
        },
      ),
    );
  }
}
