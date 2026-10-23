import '../models/expense.dart';
import '../services/category_memory.dart';

/// Spending at one merchant over a period.
class MerchantTotal {
  /// How the merchant is shown: the spelling used most often in the period.
  final String name;

  /// Net spend in base-currency minor units (refunds already taken off).
  final int total;

  /// Number of transactions behind [total], refunds included.
  final int count;

  /// The transactions behind [total], newest first.
  final List<Expense> rows;

  const MerchantTotal({
    required this.name,
    required this.total,
    required this.count,
    required this.rows,
  });
}

/// Groups the expenses in [rows] by merchant and returns them largest spend
/// first, at most [limit] of them.
///
/// Categories answer "what kind of thing"; this answers "where", which is what
/// you need to spot the one café or app quietly taking the most. Merchants are
/// matched with [CategoryMemory.merchantKey], so "Swiggy", "SWIGGY 88213" and
/// "swiggy." count as one. Income, transfers and rows without a description
/// are skipped. A refund comes off its merchant, and a merchant whose refunds
/// cancel its spending (net zero or less) is left out — it cost nothing.
List<MerchantTotal> topMerchants(
  Iterable<Expense> rows,
  int Function(Expense) baseAmountOf, {
  int limit = 5,
}) {
  final totals = <String, int>{};
  final grouped = <String, List<Expense>>{};
  final spellings = <String, Map<String, int>>{};
  for (final e in rows) {
    if (!e.isExpense) continue;
    final key = CategoryMemory.merchantKey(e.description);
    if (key.isEmpty) continue;
    totals[key] = (totals[key] ?? 0) + baseAmountOf(e);
    (grouped[key] ??= []).add(e);
    final spelling = e.description.trim();
    final counts = spellings[key] ??= {};
    counts[spelling] = (counts[spelling] ?? 0) + 1;
  }

  final result = <MerchantTotal>[
    for (final entry in totals.entries)
      if (entry.value > 0)
        MerchantTotal(
          name: _mostUsed(spellings[entry.key]!),
          total: entry.value,
          count: grouped[entry.key]!.length,
          rows: grouped[entry.key]!..sort((a, b) => b.date.compareTo(a.date)),
        ),
  ]..sort((a, b) {
      final byTotal = b.total.compareTo(a.total);
      if (byTotal != 0) return byTotal;
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.name.compareTo(b.name);
    });
  return result.length > limit ? result.sublist(0, limit) : result;
}

/// The most frequent spelling. Ties go to the shortest — "Swiggy" over the
/// bank's "SWIGGY 88213" — then the alphabetically first, so the label doesn't
/// flip between rebuilds.
String _mostUsed(Map<String, int> counts) {
  String? best;
  var bestCount = 0;
  for (final entry in counts.entries) {
    if (entry.value > bestCount ||
        (entry.value == bestCount && _shorterOrFirst(entry.key, best!))) {
      best = entry.key;
      bestCount = entry.value;
    }
  }
  return best!;
}

bool _shorterOrFirst(String a, String b) =>
    a.length != b.length ? a.length < b.length : a.compareTo(b) < 0;
