import 'package:flutter/material.dart';
import '../models/goal.dart';
import '../services/db_service.dart';

class GoalProvider extends ChangeNotifier {
  List<Goal> _goals = [];

  List<Goal> get goals => _goals;

  /// Total saved across every goal, in minor units.
  int get totalSaved => _goals.fold(0, (sum, g) => sum + g.savedAmount);

  /// Combined target across every goal, in minor units.
  int get totalTarget => _goals.fold(0, (sum, g) => sum + g.targetAmount);

  Future<void> fetchGoals() async {
    _goals = await DBService().getGoals();
    notifyListeners();
  }

  Future<void> addGoal(Goal goal) async {
    await DBService().insertGoal(goal);
    await fetchGoals();
  }

  Future<void> updateGoal(Goal goal) async {
    await DBService().updateGoal(goal);
    await fetchGoals();
  }

  Future<void> deleteGoal(int id) async {
    await DBService().deleteGoal(id);
    await fetchGoals();
  }

  /// Adds [amount] minor units to a goal's saved total (a contribution). A
  /// negative [amount] withdraws, but the saved total never drops below zero.
  Future<void> addContribution(Goal goal, int amount) async {
    final next = goal.savedAmount + amount;
    goal.savedAmount = next < 0 ? 0 : next;
    await DBService().updateGoal(goal);
    await fetchGoals();
  }
}
