import 'package:flutter/material.dart';

/// Deterministic category → icon mapping, the companion to [CategoryColors].
///
/// Built-in categories (and a handful of common synonyms) get a hand-picked
/// icon; anything else falls back to a stable icon chosen from a small pool by
/// a code-unit hash, so a custom category keeps the same icon across screens
/// and restarts (String.hashCode is not stable across Dart releases).
IconData categoryIcon(String category) {
  final key = category.trim().toLowerCase();
  final mapped = _byName[key];
  if (mapped != null) return mapped;

  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash + unit) % _fallback.length;
  }
  return _fallback[hash];
}

const Map<String, IconData> _byName = {
  // Expenses
  'food': Icons.restaurant,
  'groceries': Icons.local_grocery_store,
  'transport': Icons.directions_bus,
  'travel': Icons.flight,
  'fuel': Icons.local_gas_station,
  'shopping': Icons.shopping_bag,
  'bills': Icons.receipt_long,
  'rent': Icons.home,
  'utilities': Icons.bolt,
  'entertainment': Icons.movie,
  'subscriptions': Icons.subscriptions,
  'health': Icons.favorite,
  'medical': Icons.local_hospital,
  'education': Icons.school,
  'fitness': Icons.fitness_center,
  'insurance': Icons.verified_user,
  'kids': Icons.child_care,
  'pets': Icons.pets,
  'gifts': Icons.card_giftcard,
  'charity': Icons.volunteer_activism,
  'taxes': Icons.account_balance,
  'other': Icons.category,
  // Income / sources
  'salary': Icons.payments,
  'business': Icons.work,
  'interest': Icons.savings,
  'dividends': Icons.trending_up,
  'gift': Icons.card_giftcard,
  'refund': Icons.assignment_return,
  'bonus': Icons.emoji_events,
};

/// Neutral icons for categories not in [_byName]; picked deterministically.
const List<IconData> _fallback = [
  Icons.label,
  Icons.category,
  Icons.sell,
  Icons.bookmark,
  Icons.local_offer,
  Icons.donut_large,
];
