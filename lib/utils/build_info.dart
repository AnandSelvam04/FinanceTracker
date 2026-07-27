// Build identity, injected at compile time via --dart-define so a running
// app can be traced back to the exact source it was built from.
//
// CI passes both values (see .github/workflows/ci.yml). A plain local
// `flutter run`/`flutter build` passes neither, and shows "dev (local)".

class BuildInfo {
  BuildInfo._();

  /// App version from pubspec, e.g. "1.2.0+3".
  static const String version =
      String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  /// Short commit SHA the build came from, e.g. "be292ae".
  static const String commit =
      String.fromEnvironment('GIT_SHA', defaultValue: 'local');

  /// One-line label for the Settings screen, e.g. "1.2.0+3 (be292ae)".
  static String get label => '$version ($commit)';
}
