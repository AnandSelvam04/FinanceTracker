import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/goal.dart';
import 'package:finance_tracker/providers/goal_provider.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  // Isolate this file's database so concurrently running test files
  // can't clear each other's data (they all share one ffi process).
  DBService.dbNameOverride = 'goal_test.db';

  group('Goal model', () {
    test('progress, remaining and completeness derive from the amounts', () {
      final goal = Goal(name: 'Trip', targetAmount: 100000, savedAmount: 25000);
      expect(goal.progress, closeTo(0.25, 1e-9));
      expect(goal.remaining, 75000);
      expect(goal.isComplete, isFalse);

      goal.savedAmount = 100000;
      expect(goal.progress, 1.0);
      expect(goal.remaining, 0);
      expect(goal.isComplete, isTrue);
    });

    test('progress clamps and never divides by zero', () {
      // Over-saved clamps to 1.0.
      final over = Goal(name: 'x', targetAmount: 1000, savedAmount: 5000);
      expect(over.progress, 1.0);
      expect(over.remaining, 0);

      // A zero target reads as complete rather than dividing by zero.
      final zero = Goal(name: 'y', targetAmount: 0, savedAmount: 0);
      expect(zero.progress, 1.0);
    });

    test('round-trips through toMap/fromMap including the optional date', () {
      final goal = Goal(
        id: 7,
        name: 'Emergency Fund',
        targetAmount: 500000,
        savedAmount: 120000,
        targetDate: DateTime(2027, 3, 1),
      );
      final restored = Goal.fromMap(goal.toMap());
      expect(restored.id, 7);
      expect(restored.name, 'Emergency Fund');
      expect(restored.targetAmount, 500000);
      expect(restored.savedAmount, 120000);
      expect(restored.targetDate, DateTime(2027, 3, 1));

      // A null date survives the round-trip as null.
      final noDate = Goal.fromMap(
          Goal(name: 'z', targetAmount: 100).toMap());
      expect(noDate.targetDate, isNull);
      expect(noDate.savedAmount, 0);
    });
  });

  group('GoalProvider', () {
    late GoalProvider provider;

    setUp(() async {
      await DBService().clearAll();
      provider = GoalProvider();
    });

    tearDown(() async => DBService().clearAll());

    test('add, fetch and totals', () async {
      await provider.addGoal(Goal(name: 'Car', targetAmount: 800000));
      await provider.addGoal(
          Goal(name: 'Laptop', targetAmount: 150000, savedAmount: 50000));

      expect(provider.goals.length, 2);
      expect(provider.totalTarget, 950000);
      expect(provider.totalSaved, 50000);
    });

    test('addContribution increases the saved amount and persists', () async {
      await provider.addGoal(Goal(name: 'Trip', targetAmount: 100000));
      final goal = provider.goals.single;

      await provider.addContribution(goal, 30000);
      expect(provider.goals.single.savedAmount, 30000);

      // Re-fetch from the database to confirm it was persisted, not just held
      // in memory.
      final reloaded = GoalProvider();
      await reloaded.fetchGoals();
      expect(reloaded.goals.single.savedAmount, 30000);
    });

    test('a withdrawal never drives the saved amount below zero', () async {
      await provider.addGoal(
          Goal(name: 'Fund', targetAmount: 100000, savedAmount: 20000));
      final goal = provider.goals.single;

      await provider.addContribution(goal, -50000);
      expect(provider.goals.single.savedAmount, 0);
    });

    test('update and delete', () async {
      await provider.addGoal(Goal(name: 'Old', targetAmount: 1000));
      final goal = provider.goals.single;

      await provider.updateGoal(Goal(
        id: goal.id,
        name: 'New',
        targetAmount: 2000,
        savedAmount: 500,
      ));
      expect(provider.goals.single.name, 'New');
      expect(provider.goals.single.targetAmount, 2000);

      await provider.deleteGoal(goal.id!);
      expect(provider.goals, isEmpty);
    });
  });
}
