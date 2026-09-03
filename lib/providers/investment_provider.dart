import 'package:flutter/material.dart';
import '../models/investment.dart';
import '../services/db_service.dart';

/// The time buckets the per-type investment breakdown can be grouped into.
enum InvestmentPeriod { weekly, monthly, yearly }

class InvestmentProvider extends ChangeNotifier {
  List<Investment> _investments = [];

  List<Investment> get investments => _investments;

  /// Total invested across every contribution, in minor units.
  int get totalInvested =>
      _investments.fold<int>(0, (sum, i) => sum + i.amount);

  /// Sum of contributions grouped by type, in minor units. Ordered by total
  /// invested (largest first) so the biggest holdings surface at the top.
  List<MapEntry<String, int>> totalsByType() {
    final totals = <String, int>{};
    for (final i in _investments) {
      totals[i.type] = (totals[i.type] ?? 0) + i.amount;
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  /// Every contribution of [type], newest first (the fetch order).
  List<Investment> ofType(String type) =>
      _investments.where((i) => i.type == type).toList();

  /// Distinct investment types the user has actually used, sorted. Lets the
  /// Add screen offer previously entered custom types (e.g. Crypto, PPF) so a
  /// type only has to be typed once.
  List<String> usedTypes() =>
      (_investments.map((i) => i.type).toSet().toList())..sort();

  /// The group key for [date] under [period]. Weekly buckets by the Monday of
  /// the week (ISO date), so keys sort chronologically as plain strings.
  static String periodKey(DateTime date, InvestmentPeriod period) {
    switch (period) {
      case InvestmentPeriod.weekly:
        // Step back in calendar days rather than by a Duration: subtracting
        // 24-hour blocks across a fall-back DST boundary lands on Sunday
        // 23:00 and buckets the row into the wrong week.
        final monday =
            DateTime(date.year, date.month, date.day - (date.weekday - 1));
        return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
      case InvestmentPeriod.monthly:
        return '${date.year}-${date.month.toString().padLeft(2, '0')}';
      case InvestmentPeriod.yearly:
        return '${date.year}';
    }
  }

  /// Contributions of [type] grouped into [period] buckets, newest bucket
  /// first, each bucket's entries newest first. Powers the weekly/monthly/
  /// yearly breakdown on the type detail screen.
  Map<String, List<Investment>> breakdownByPeriod(
      String type, InvestmentPeriod period) {
    final byKey = <String, List<Investment>>{};
    for (final i in ofType(type)) {
      byKey.putIfAbsent(periodKey(i.date, period), () => []).add(i);
    }
    final ordered = byKey.keys.toList()..sort((a, b) => b.compareTo(a));
    return {for (final k in ordered) k: byKey[k]!};
  }

  /// Contributions of [type] grouped by name — e.g. the individual funds
  /// within "Mutual Funds", so each fund's total surfaces on its own instead
  /// of being lumped into the type. Groups are ordered by total invested
  /// (largest first) and each group keeps its entries newest first (the fetch
  /// order).
  Map<String, List<Investment>> breakdownByName(String type) {
    final byName = <String, List<Investment>>{};
    for (final i in ofType(type)) {
      byName.putIfAbsent(i.name, () => []).add(i);
    }
    final totalOf = <String, int>{
      for (final e in byName.entries)
        e.key: e.value.fold<int>(0, (sum, i) => sum + i.amount),
    };
    final ordered = byName.keys.toList()
      ..sort((a, b) {
        final byTotal = totalOf[b]!.compareTo(totalOf[a]!);
        // Fall back to name so ties (and equal-total funds) stay stable and
        // alphabetical rather than jumping around between rebuilds.
        return byTotal != 0 ? byTotal : a.toLowerCase().compareTo(b.toLowerCase());
      });
    return {for (final k in ordered) k: byName[k]!};
  }

  /// Contributions of [type] grouped by calendar month keyed as `YYYY-MM`,
  /// newest month first, with each month's entries newest first. This powers
  /// the "how much did I invest in this month/year" breakdown.
  Map<String, List<Investment>> monthlyBreakdown(String type) {
    final byMonth = <String, List<Investment>>{};
    for (final i in ofType(type)) {
      final key = '${i.date.year}-${i.date.month.toString().padLeft(2, '0')}';
      byMonth.putIfAbsent(key, () => []).add(i);
    }
    final ordered = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
    return {for (final k in ordered) k: byMonth[k]!};
  }

  Future<void> fetchInvestments() async {
    _investments = await DBService().getInvestments();
    notifyListeners();
  }

  Future<void> addInvestment(Investment investment) async {
    await DBService().insertInvestment(investment);
    await fetchInvestments();
  }

  Future<void> updateInvestment(Investment investment) async {
    await DBService().updateInvestment(investment);
    await fetchInvestments();
  }

  Future<void> deleteInvestment(int id) async {
    await DBService().deleteInvestment(id);
    await fetchInvestments();
  }

  /// Moves every contribution of [from] to [to] — for fixing a contribution
  /// filed under the wrong type. Returns the number of contributions moved.
  Future<int> reassignType(String from, String to) async {
    final moved = await DBService().reassignInvestmentType(from, to);
    if (moved > 0) await fetchInvestments();
    return moved;
  }
}
