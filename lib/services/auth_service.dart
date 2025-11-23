import 'package:local_auth/local_auth.dart';

class AuthService {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> canCheckBiometrics() async {
    return await _auth.canCheckBiometrics;
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Please authenticate to access FinanceTracker',
        biometricOnly: true,
      );
    } catch (e) {
      return false;
    }
  }

  Future<bool> authenticateWithPin(String pin, String correctPin) async {
    // In production, store the correctPin securely (not hardcoded)
    return pin == correctPin;
  }
}
