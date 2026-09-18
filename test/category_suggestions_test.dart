import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/utils/category_suggestions.dart';

void main() {
  group('budgetCategorySuggestions', () {
    test('used categories come before defaults, in order', () {
      final result = budgetCategorySuggestions(
        used: ['Groceries', 'Fuel'],
        defaults: ['Food', 'Transport'],
      );
      expect(result, ['Groceries', 'Fuel', 'Food', 'Transport']);
    });

    test('de-duplicates case-insensitively, keeping the used spelling', () {
      // The user files spend under "groceries"; the default is "Groceries".
      // The real spelling must win so a budget matches the spend it tracks.
      final result = budgetCategorySuggestions(
        used: ['groceries'],
        defaults: ['Groceries', 'Food'],
      );
      expect(result, ['groceries', 'Food']);
      expect(result.where((c) => c.toLowerCase() == 'groceries').length, 1);
    });

    test('trims and drops blank entries', () {
      final result = budgetCategorySuggestions(
        used: ['  Food  ', '', '   '],
        defaults: ['Bills'],
      );
      expect(result, ['Food', 'Bills']);
    });

    test('collapses duplicates within the used list itself', () {
      final result = budgetCategorySuggestions(
        used: ['Food', 'FOOD', 'food'],
        defaults: const [],
      );
      expect(result, ['Food']);
    });

    test('empty inputs yield an empty list', () {
      expect(
        budgetCategorySuggestions(used: const [], defaults: const []),
        isEmpty,
      );
    });
  });
}
