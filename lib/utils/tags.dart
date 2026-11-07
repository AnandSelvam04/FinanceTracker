import '../models/expense.dart';

/// #tags written in a transaction's note — "#goa-trip", "#office" — so a set
/// of transactions can be grouped and totalled across categories and months.
/// Letters, digits, `_` and `-`; matched case-insensitively.
final _tag = RegExp(r'(?:^|[^\p{L}\p{N}_&])#([\p{L}\p{N}_-]*[\p{L}\p{N}])',
    unicode: true);

/// The tags in [text], lower-cased, in the order they first appear.
List<String> tagsIn(String? text) {
  if (text == null || text.isEmpty) return const [];
  final out = <String>[];
  for (final m in _tag.allMatches(text)) {
    final t = m.group(1)!.toLowerCase();
    if (!out.contains(t)) out.add(t);
  }
  return out;
}

/// The tags on [e]: from its note, and from its description too (where a
/// voice entry or a quick note may have put them).
List<String> tagsOf(Expense e) =>
    {...tagsIn(e.note), ...tagsIn(e.description)}.toList();

/// One tag's transactions and what they add up to.
class TagSummary {
  final String tag;
  final List<Expense> transactions;

  /// Spent, refunds taken off, in the base currency.
  final int spent;

  /// Income tagged with it, in the base currency.
  final int income;

  const TagSummary({
    required this.tag,
    required this.transactions,
    required this.spent,
    required this.income,
  });
}

/// Every tag across [expenses], most spent first. [toBase] converts a row's
/// amount to the base currency. Transfers are listed but add to neither
/// total.
List<TagSummary> tagSummaries(
    List<Expense> expenses, int Function(Expense e) toBase) {
  final rows = <String, List<Expense>>{};
  for (final e in expenses) {
    for (final t in tagsOf(e)) {
      rows.putIfAbsent(t, () => []).add(e);
    }
  }
  final out = [
    for (final entry in rows.entries)
      TagSummary(
        tag: entry.key,
        transactions: entry.value..sort((a, b) => b.date.compareTo(a.date)),
        spent: entry.value
            .where((e) => e.isExpense)
            .fold(0, (s, e) => s + toBase(e)),
        income: entry.value
            .where((e) => e.isIncome)
            .fold(0, (s, e) => s + toBase(e)),
      )
  ]..sort((a, b) {
      final bySpent = b.spent.compareTo(a.spent);
      return bySpent != 0 ? bySpent : a.tag.compareTo(b.tag);
    });
  return out;
}
