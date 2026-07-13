import 'dart:developer' as developer;

/// Central logging helper so failures are visible in dev tools
/// without leaking into release console output via print().
class AppLogger {
  AppLogger._();

  static void info(String message) {
    developer.log(message, name: 'FinanceTracker');
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(
      message,
      name: 'FinanceTracker',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
