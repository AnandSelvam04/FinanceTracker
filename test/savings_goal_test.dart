import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/savings_goal.dart';
import 'package:finance_tracker/providers/goal_provider.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('SavingsGoal math', () {
    final now = DateTime(2026, 9, 25);

    test('monthly need spreads the remainder, rounding up', () {
      final goal = SavingsGoal(
        name: 'Trip',
        target: 100000,
        saved: 10000,
        // Sep..Dec inclusive = 4 months.
        targetDate: DateTime(2026, 12, 15),
      );
      expect(goal.monthsLeft(now), 4);
      expect(goal.monthlyNeeded(now), 22500);

      final uneven = goal.copyWith(saved: 0, target: 100001);
      expect(uneven.monthlyNeeded(now), 25001);
    });

    test('a deadline later this month asks for the whole remainder', () {
      final goal = SavingsGoal(
          name: 'Gift', target: 5000, targetDate: DateTime(2026, 9, 30));
      expect(goal.monthsLeft(now), 1);
      expect(goal.monthlyNeeded(now), 5000);
      expect(goal.isOverdue(now), isFalse);
    });

    test('a passed deadline is overdue until the target is met', () {
      final goal = SavingsGoal(
          name: 'Phone',
          target: 5000,
          saved: 1000,
          targetDate: DateTime(2026, 9, 1));
      expect(goal.monthsLeft(now), 0);
      expect(goal.isOverdue(now), isTrue);
      expect(goal.monthlyNeeded(now), 4000);
      expect(goal.copyWith(saved: 5000).isOverdue(now), isFalse);
    });

    test('no deadline, or complete, means no monthly need', () {
      expect(const SavingsGoal(name: 'Fund', target: 5000).monthlyNeeded(now),
          isNull);
      final done = SavingsGoal(
          name: 'Done',
          target: 5000,
          saved: 6000,
          targetDate: DateTime(2027, 1, 1));
      expect(done.isComplete, isTrue);
      expect(done.progress, 1.0);
      expect(done.remaining, 0);
      expect(done.monthlyNeeded(now), isNull);
    });

    test('copyWith can clear the target date', () {
      final goal =
          SavingsGoal(name: 'X', target: 1, targetDate: DateTime(2027, 1, 1));
      expect(goal.copyWith(clearTargetDate: true).targetDate, isNull);
      expect(goal.copyWith(name: 'Y').targetDate, DateTime(2027, 1, 1));
    });

    test('sortGoals puts dated, then undated, then reached goals', () {
      final sorted = GoalProvider.sortGoals([
        const SavingsGoal(name: 'Reached', target: 10, saved: 10),
        const SavingsGoal(name: 'b undated', target: 10),
        SavingsGoal(name: 'Later', target: 10, targetDate: DateTime(2027)),
        SavingsGoal(name: 'Sooner', target: 10, targetDate: DateTime(2026, 12)),
        const SavingsGoal(name: 'A undated', target: 10),
      ]);
      expect(sorted.map((g) => g.name),
          ['Sooner', 'Later', 'A undated', 'b undated', 'Reached']);
    });
  });

  group('GoalProvider persistence', () {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DBService.testFactory = databaseFactoryFfi;
    DBService.dbNameOverride = 'savings_goal_test.db';

    late GoalProvider provider;

    setUp(() async {
      await DBService().clearAll();
      provider = GoalProvider();
    });

    tearDown(() async => DBService().clearAll());

    test('goals round-trip through the database', () async {
      await provider.addGoal(SavingsGoal(
        name: 'Emergency fund',
        target: 50000000,
        saved: 1250000,
        targetDate: DateTime(2027, 6, 30),
        color: 0xFF00897B,
      ));
      expect(provider.goals, hasLength(1));
      final g = provider.goals.single;
      expect(g.id, isNotNull);
      expect(g.name, 'Emergency fund');
      expect(g.target, 50000000);
      expect(g.saved, 1250000);
      expect(g.targetDate, DateTime(2027, 6, 30));
      expect(g.color, 0xFF00897B);
      expect(provider.totalSaved, 1250000);
      expect(provider.totalTarget, 50000000);
    });

    test('contribute adds and withdraws, never below zero', () async {
      await provider.addGoal(const SavingsGoal(name: 'Trip', target: 10000));
      var goal = provider.goals.single;

      goal = await provider.contribute(goal, 4000);
      expect(provider.goals.single.saved, 4000);

      goal = await provider.contribute(goal, -1500);
      expect(provider.goals.single.saved, 2500);

      await provider.contribute(goal, -99999);
      expect(provider.goals.single.saved, 0);
    });

    test('deleteGoal removes it', () async {
      await provider.addGoal(const SavingsGoal(name: 'Gone', target: 1));
      await provider.deleteGoal(provider.goals.single.id!);
      expect(provider.goals, isEmpty);
    });
  });
}
