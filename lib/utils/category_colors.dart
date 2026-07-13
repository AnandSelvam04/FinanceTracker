import 'package:flutter/material.dart';

/// Deterministic category → color mapping shared by all charts,
/// so a category keeps the same color across screens and app restarts.
class CategoryColors {
  CategoryColors._();

  static const List<Color> palette = [
    Color(0xFF1E88E5), // blue
    Color(0xFF43A047), // green
    Color(0xFFFB8C00), // orange
    Color(0xFF8E24AA), // purple
    Color(0xFFE53935), // red
    Color(0xFF00897B), // teal
    Color(0xFF6D4C41), // brown
    Color(0xFF3949AB), // indigo
    Color(0xFFD81B60), // pink
    Color(0xFF7CB342), // light green
    Color(0xFF00ACC1), // cyan
    Color(0xFFFFB300), // amber
  ];

  static const Map<String, Color> _builtIn = {
    'Food': Color(0xFFFB8C00),
    'Transport': Color(0xFF1E88E5),
    'Shopping': Color(0xFFD81B60),
    'Bills': Color(0xFF8E24AA),
    'Entertainment': Color(0xFFE53935),
    'Health': Color(0xFF43A047),
    'Education': Color(0xFF3949AB),
    'Other': Color(0xFF6D4C41),
  };

  static Color forCategory(String category) {
    final builtIn = _builtIn[category];
    if (builtIn != null) return builtIn;
    // String.hashCode is not guaranteed stable across Dart releases,
    // so use a simple code-unit sum for a persistent fallback.
    var hash = 0;
    for (final unit in category.codeUnits) {
      hash = (hash + unit) % palette.length;
    }
    return palette[hash];
  }
}
