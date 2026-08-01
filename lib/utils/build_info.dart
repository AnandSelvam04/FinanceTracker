import 'package:package_info_plus/package_info_plus.dart';

import 'app_logger.dart';

/// Build identity: which version is installed, and — for CI builds — the
/// commit it came from.
///
/// The version is read from the installed package at startup, which Flutter
/// populates from `pubspec.yaml` on every build path. It used to come only
/// from a `--dart-define` that CI passes, so a locally built and sideloaded
/// APK reported "dev" no matter which version it actually was.
///
/// The commit still comes from a define, since nothing but CI knows it.
class BuildInfo {
  BuildInfo._();

  /// Version injected by CI, e.g. "1.3.0+5". Empty for a local build.
  static const String _definedVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '');

  /// Short commit SHA the build came from, e.g. "be292ae". [unknownCommit]
  /// when the build was not made by CI.
  static const String commit =
      String.fromEnvironment('GIT_SHA', defaultValue: unknownCommit);

  static const String unknownCommit = 'local';

  static String _packageVersion = '';

  /// Reads the installed package's version. Call once at startup, before
  /// runApp; safe to call again. Failure is not fatal — the version simply
  /// falls back, so a plugin problem cannot stop the app launching.
  static Future<void> load() async {
    if (_definedVersion.isNotEmpty) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final build = info.buildNumber;
      _packageVersion =
          build.isEmpty ? info.version : '${info.version}+$build';
    } catch (e, s) {
      AppLogger.error('Reading the package version failed', e, s);
    }
  }

  /// The app version, preferring what CI injected, then what the installed
  /// package reports, and only then admitting it does not know.
  static String get version {
    if (_definedVersion.isNotEmpty) return _definedVersion;
    if (_packageVersion.isNotEmpty) return _packageVersion;
    return 'dev';
  }

  /// Whether this build can be traced back to a specific commit.
  static bool get hasCommit => commit != unknownCommit;

  /// One-line label for the Settings screen: "1.3.0+5 (be292ae)" for a CI
  /// build, or just "1.3.0+5" locally, where the commit adds nothing.
  static String get label => hasCommit ? '$version ($commit)' : version;
}
