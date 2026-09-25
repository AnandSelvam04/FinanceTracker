import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/utils/alerts.dart';

void main() {
  group('budgetPace', () {
    test('extrapolates average daily spend to month end', () {
      // September has 30 days; 10 days in, 4000 spent -> 12000 projected.
      final pace = budgetPace(
        spent: 4000,
        cap: 10000,
        year: 2026,
        month: 9,
        now: DateTime(2026, 9, 10, 18),
      )!;
      expect(pace.projected, 12000);
      expect(pace.daysLeft, 20);
      expect(pace.onTrackToOverspend, isTrue);
    });

    test('an under-pace budget reports a per-day allowance', () {
      final pace = budgetPace(
        spent: 3000,
        cap: 10000,
        year: 2026,
        month: 9,
        now: DateTime(2026, 9, 16),
      )!;
      expect(pace.onTrackToOverspend, isFalse);
      // 7000 left over today plus the 14 days after it.
      expect(pace.dailyAllowance, 7000 ~/ 15);
    });

    test('the last day offers the whole remainder', () {
      final pace = budgetPace(
        spent: 9000,
        cap: 10000,
        year: 2026,
        month: 9,
        now: DateTime(2026, 9, 30),
      )!;
      expect(pace.daysLeft, 0);
      expect(pace.dailyAllowance, 1000);
    });

    test('already over the cap is not "on track to overspend"', () {
      final pace = budgetPace(
        spent: 11000,
        cap: 10000,
        year: 2026,
        month: 9,
        now: DateTime(2026, 9, 20),
      )!;
      expect(pace.onTrackToOverspend, isFalse);
      expect(pace.dailyAllowance, 0);
    });

    test('stays quiet early in the month, for other months, and without a cap',
        () {
      BudgetPace? at(DateTime now, {int cap = 10000}) =>
          budgetPace(spent: 2000, cap: cap, year: 2026, month: 9, now: now);
      expect(at(DateTime(2026, 9, 2)), isNull);
      expect(at(DateTime(2026, 9, kMinPaceDays)), isNotNull);
      expect(at(DateTime(2026, 10, 15)), isNull);
      expect(at(DateTime(2026, 8, 15)), isNull);
      expect(at(DateTime(2026, 9, 15), cap: 0), isNull);
    });

    test('daysInMonth handles leap years', () {
      expect(daysInMonth(2028, 2), 29);
      expect(daysInMonth(2026, 2), 28);
      expect(daysInMonth(2026, 12), 31);
    });
  });
}
