/// Category suggestion helpers, kept free of Flutter/DB dependencies so they
/// can be unit-tested and reused by any picker.

/// Ordered, de-duplicated category suggestions for the budgets picker.
///
/// A budget only tracks spend when its category string matches the one on the
/// transactions exactly (see the budgets screen's `spentForBudget`). Typing a
/// budget for "Groceries" while filing spend under "groceries" silently shows
/// zero spent and never alerts. Offering the real category spellings as chips
/// removes that footgun and matches the Add Expense picker.
///
/// [used] are the category names as they actually appear on transactions (and
/// on existing budgets), most relevant first; their spelling is preserved so a
/// chosen budget category lines up with the spend it caps. [defaults] fill in
/// common categories the user has not used yet. Entries are de-duplicated
/// case-insensitively, keeping the first spelling seen — so a real "groceries"
/// wins over a default "Groceries".
List<String> budgetCategorySuggestions({
  required Iterable<String> used,
  required Iterable<String> defaults,
}) {
  final result = <String>[];
  final seen = <String>{};
  for (final raw in [...used, ...defaults]) {
    final name = raw.trim();
    if (name.isEmpty) continue;
    if (seen.add(name.toLowerCase())) result.add(name);
  }
  return result;
}
