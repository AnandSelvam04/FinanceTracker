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
}
