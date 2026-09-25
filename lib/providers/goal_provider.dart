import 'package:flutter/material.dart';
import '../models/savings_goal.dart';
import '../services/db_service.dart';

class GoalProvider extends ChangeNotifier {
  List<SavingsGoal> _goals = [];

  /// Goals in progress first (nearest deadline, then undated), then the ones
  /// already reached — so what still needs money stays on top.
  List<SavingsGoal> get goals => _goals;

  /// Sum of every goal's saved amount, in minor units.
  int get totalSaved => _goals.fold(0, (sum, g) => sum + g.saved);

  /// Sum of every goal's target, in minor units.
  int get totalTarget => _goals.fold(0, (sum, g) => sum + g.target);

  Future<void> fetchGoals() async {
    _goals = sortGoals(await DBService().getGoals());
    notifyListeners();
  }

  Future<void> addGoal(SavingsGoal goal) async {
    await DBService().insertGoal(goal);
    await fetchGoals();
  }

  Future<void> updateGoal(SavingsGoal goal) async {
    await DBService().updateGoal(goal);
    await fetchGoals();
  }

  Future<void> deleteGoal(int id) async {
    await DBService().deleteGoal(id);
    await fetchGoals();
  }

  /// Adds [delta] minor units to a goal's saved amount (negative to withdraw),
  /// never letting it drop below zero. Returns the updated goal.
  Future<SavingsGoal> contribute(SavingsGoal goal, int delta) async {
    final next = goal.saved + delta;
    final updated = goal.copyWith(saved: next < 0 ? 0 : next);
    await updateGoal(updated);
    return updated;
  }

  /// Ordering used by [goals]; exposed for tests.
  static List<SavingsGoal> sortGoals(List<SavingsGoal> goals) {
    int rank(SavingsGoal g) =>
        g.isComplete ? 2 : (g.targetDate == null ? 1 : 0);
    return [...goals]..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        if (a.targetDate != null && b.targetDate != null) {
          final d = a.targetDate!.compareTo(b.targetDate!);
          if (d != 0) return d;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }
}
