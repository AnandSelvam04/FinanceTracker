import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/utils/category_icons.dart';

void main() {
  test('known categories map to their icon, case-insensitively', () {
    expect(categoryIcon('Food'), Icons.restaurant);
    expect(categoryIcon('food'), Icons.restaurant);
    expect(categoryIcon('  BILLS '), Icons.receipt_long);
    expect(categoryIcon('Salary'), Icons.payments);
  });

  test('an unknown category gets a stable fallback icon', () {
    final first = categoryIcon('Nebula');
    final second = categoryIcon('Nebula');
    // Deterministic across calls (same input, same icon).
    expect(first, second);
    // A different custom name still resolves to a real icon.
    expect(categoryIcon('Zebra'), isA<IconData>());
  });
}
