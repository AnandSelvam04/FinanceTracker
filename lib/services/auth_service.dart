import 'package:local_auth/local_auth.dart';

import '../l10n/app_localizations.dart';

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

  Future<bool> canAuthenticate() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Biometrics with device credential (PIN/pattern) fallback.
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        // No BuildContext here (called before the app tree is up), so resolve
        // against the device locale.
        localizedReason: AppLocalizations.resolve().authReason,
      );
    } catch (e) {
      return false;
    }
  }
}
