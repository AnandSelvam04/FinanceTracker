import 'package:finance_tracker/services/backup/drive_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

void main() {
  group('DriveStore.messageFor', () {
    test('an unregistered build points to the set-up guide', () {
      for (final (code, detail) in [
        (GoogleSignInExceptionCode.unknownError,
            'SDK reported an exception: ApiException: 10: '),
        (GoogleSignInExceptionCode.clientConfigurationError, null),
        (GoogleSignInExceptionCode.providerConfigurationError, 'x'),
        (null, 'sign_in_failed DEVELOPER_ERROR'),
      ]) {
        expect(DriveStore.messageFor(code, detail),
            contains('GOOGLE_DRIVE_SETUP.md'),
            reason: '$code $detail');
      }
    });

    test('a cancelled picker says so', () {
      expect(DriveStore.messageFor(GoogleSignInExceptionCode.canceled, null),
          'Google sign-in was cancelled.');
    });

    test('a network failure asks to check the connection', () {
      expect(
          DriveStore.messageFor(
              GoogleSignInExceptionCode.unknownError, 'network_error'),
          contains('Check your connection'));
    });

    test('anything else names the code and keeps the data-is-safe line', () {
      final message = DriveStore.messageFor(
          GoogleSignInExceptionCode.interrupted, 'whatever');
      expect(message, contains('interrupted'));
      expect(message, contains('Your data is safe'));
    });
  });
}
