import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/utils/category_colors.dart';

void main() {
  group('CategoryColors', () {
    test('same category always maps to the same color', () {
      for (final category in ['Food', 'Transport', 'CustomThing', 'चाय']) {
        expect(CategoryColors.forCategory(category),
            CategoryColors.forCategory(category));
      }
    });

    test('built-in categories all have distinct colors', () {
      const builtIns = [
        'Food',
        'Transport',
        'Shopping',
        'Bills',
        'Entertainment',
        'Health',
        'Education',
        'Other',
      ];
      final colors = builtIns.map(CategoryColors.forCategory).toSet();
      expect(colors.length, builtIns.length);
    });

    test('custom categories fall back to the palette', () {
      expect(CategoryColors.palette,
          contains(CategoryColors.forCategory('Some Custom Category')));
    });
  });

  group('CategoryColors.foreground', () {
    // Contrast ratio between two colours, per WCAG.
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    // The Material 3 dark surface the app's cards sit on.
    const darkSurface = Color(0xFF1C1B1F);

    test('light mode keeps the palette colour unchanged', () {
      for (final c in CategoryColors.palette) {
        expect(CategoryColors.foreground(c, Brightness.light), c);
      }
    });

    test('every palette colour is legible on a dark surface', () {
      for (final c in CategoryColors.palette) {
        final fg = CategoryColors.foreground(c, Brightness.dark);
        // 3:1 is the WCAG minimum for icons and other graphics.
        expect(contrast(fg, darkSurface), greaterThanOrEqualTo(3.0),
            reason: 'palette colour $c');
      }
    });

    test('keeps the hue, so categories stay distinguishable', () {
      for (final c in CategoryColors.palette) {
        final fg = CategoryColors.foreground(c, Brightness.dark);
        expect(HSLColor.fromColor(fg).hue,
            closeTo(HSLColor.fromColor(c).hue, 1.0));
      }
    });
  });
}
