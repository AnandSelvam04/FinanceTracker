import 'package:local_auth/local_auth.dart';

import '../utils/app_logger.dart';

/// How an unlock attempt ended.
enum AuthOutcome {
  /// The user proved who they are.
  success,

  /// The prompt ran and was cancelled, failed, or is briefly locked out.
  /// Stay locked; the user can try again.
  failed,

  /// The prompt cannot run on this device or build (no screen lock set, no
  /// hardware, or the Android activity cannot host it). Retrying would fail
  /// the same way forever, so the lock must not hold the user's data hostage.
  unavailable,
}

class AuthService {
  final LocalAuthentication _auth = LocalAuthentication();

  /// Grace period after backgrounding before the app re-locks, so quick
  /// app switches (e.g. copying an OTP) don't force re-authentication.
  static const Duration lockAfter = Duration(seconds: 15);

  /// Pure decision used by the lock gate and covered by unit tests.
  static bool shouldRelock({
    required DateTime? backgroundedAt,
    required DateTime now,
    Duration lockAfter = lockAfter,
  }) {
    if (backgroundedAt == null) return false;
    return now.difference(backgroundedAt) >= lockAfter;
  }

  /// Errors that no retry can fix. Anything else (a cancel, a timeout, a
  /// temporary lockout) leaves the app locked with the Unlock button.
  static const _permanent = {
    LocalAuthExceptionCode.uiUnavailable,
    LocalAuthExceptionCode.noCredentialsSet,
    LocalAuthExceptionCode.noBiometricHardware,
    LocalAuthExceptionCode.noBiometricsEnrolled,
  };

  /// Maps a failed prompt to an outcome; pure, for tests.
  static AuthOutcome outcomeForError(LocalAuthExceptionCode code) =>
      _permanent.contains(code) ? AuthOutcome.unavailable : AuthOutcome.failed;

  Future<bool> canAuthenticate() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Biometrics with device credential (PIN/pattern) fallback.
  Future<AuthOutcome> authenticate() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Please authenticate to access FinanceTracker',
      );
      return ok ? AuthOutcome.success : AuthOutcome.failed;
    } on LocalAuthException catch (e, st) {
      // Previously every error was swallowed as a plain "no", so a prompt that
      // could never open (the Android activity was not a FragmentActivity)
      // left the user on a lock screen whose Unlock button did nothing.
      AppLogger.error('App lock prompt failed', e, st);
      return outcomeForError(e.code);
    } catch (e, st) {
      AppLogger.error('App lock prompt failed', e, st);
      return AuthOutcome.failed;
    }
  }
}
