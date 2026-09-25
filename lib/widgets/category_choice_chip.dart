import 'package:flutter/material.dart';

import '../utils/category_colors.dart';
import '../utils/category_icons.dart';

/// A pickable category: its icon in its colour, with a tint and outline of
/// that colour when selected.
///
/// Material's default checkmark is drawn in place of the avatar, so a selected
/// category lost its icon to a grey tick. The tint and coloured outline show
/// the selection instead, and the icon stays visible.
class CategoryChoiceChip extends StatelessWidget {
  final String category;
  final bool selected;
  final VoidCallback onSelected;

  const CategoryChoiceChip({
    super.key,
    required this.category,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final color = CategoryColors.forCategory(category);
    return ChoiceChip(
      avatar: Icon(categoryIcon(category), size: 18, color: color),
      label: Text(category),
      selected: selected,
      showCheckmark: false,
      selectedColor: color.withValues(alpha: 0.22),
      side: selected
          ? BorderSide(color: color, width: 1.5)
          : BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      onSelected: (_) => onSelected(),
    );
  }
}

/// True when [typed] names [category], ignoring case and surrounding spaces,
/// so "food " and "Food" are the same category.
bool isSameCategory(String typed, String category) =>
    typed.trim().toLowerCase() == category.trim().toLowerCase();
