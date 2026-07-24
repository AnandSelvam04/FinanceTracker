import 'package:flutter/material.dart';
import '../models/investment.dart';
import '../services/db_service.dart';

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

  /// Contributions of [type] grouped by calendar month keyed as `YYYY-MM`,
  /// newest month first, with each month's entries newest first. This powers
  /// the "how much did I invest in this month/year" breakdown.
  Map<String, List<Investment>> monthlyBreakdown(String type) {
    final byMonth = <String, List<Investment>>{};
    for (final i in ofType(type)) {
      final key =
          '${i.date.year}-${i.date.month.toString().padLeft(2, '0')}';
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
}
