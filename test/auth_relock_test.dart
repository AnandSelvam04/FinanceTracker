import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/services/auth_service.dart';

void main() {
  group('AuthService.shouldRelock', () {
    final now = DateTime(2026, 7, 14, 12, 0, 0);

    test('never re-locks when the app was not backgrounded', () {
      expect(
        AuthService.shouldRelock(backgroundedAt: null, now: now),
        isFalse,
      );
    });

    test('does not re-lock within the grace period', () {
      final backgrounded = now.subtract(const Duration(seconds: 5));
      expect(
        AuthService.shouldRelock(backgroundedAt: backgrounded, now: now),
        isFalse,
      );
    });

    test('re-locks once the grace period has elapsed', () {
      final backgrounded = now.subtract(const Duration(seconds: 30));
      expect(
        AuthService.shouldRelock(backgroundedAt: backgrounded, now: now),
        isTrue,
      );
    });

    test('re-locks exactly at the threshold', () {
      final backgrounded = now.subtract(AuthService.lockAfter);
      expect(
        AuthService.shouldRelock(backgroundedAt: backgrounded, now: now),
        isTrue,
      );
    });

    test('honors a custom lockAfter duration', () {
      final backgrounded = now.subtract(const Duration(minutes: 2));
      expect(
        AuthService.shouldRelock(
          backgroundedAt: backgrounded,
          now: now,
          lockAfter: const Duration(minutes: 5),
        ),
        isFalse,
      );
    });
  });
}
