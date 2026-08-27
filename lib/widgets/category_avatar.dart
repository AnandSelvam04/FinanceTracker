import 'package:flutter/material.dart';
import '../utils/category_colors.dart';
import '../utils/category_icons.dart';

/// The app's standard way to depict a spending category: its icon in its
/// colour on a tint of that colour. Used wherever a category is listed so the
/// same category looks identical across the dashboard, transactions, budgets,
/// and reports.
class CategoryAvatar extends StatelessWidget {
  final String category;
  final double radius;

  const CategoryAvatar({super.key, required this.category, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final color = CategoryColors.forCategory(category);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: dark ? 0.28 : 0.15),
      child: Icon(categoryIcon(category), color: color, size: radius * 1.1),
    );
  }
}
