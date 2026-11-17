import 'package:finance_tracker/services/backup/backup_errors.dart';
import 'package:finance_tracker/services/backup/drive_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers authorization requests the way Android does: a token when this
/// app has been given access (or the user allows it at a prompt), none when
/// asking silently without it.
class _FakeGoogle extends GoogleSignInPlatform with MockPlatformInterfaceMixin {
  final requests = <AuthorizationRequestDetails>[];
  bool granted = false;
  bool userAllows = true;
  int signOuts = 0;

  @override
  Future<void> init(InitParameters params) async {}

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(
          AttemptLightweightAuthenticationParameters params) =>
      null;

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) =>
      throw StateError('Drive backup must never sign in');

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
      ClientAuthorizationTokensForScopesParameters params) async {
    requests.add(params.request);
    if (!granted && params.request.promptIfUnauthorized) {
      if (!userAllows) {
        throw const GoogleSignInException(
            code: GoogleSignInExceptionCode.canceled);
      }
      granted = true;
    }
    return granted
        ? const ClientAuthorizationTokenData(accessToken: 't')
        : null;
  }

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
          ServerAuthorizationTokensForScopesParameters params) async =>
      null;

  @override
  Future<void> signOut(SignOutParams params) async => signOuts++;

  @override
  Future<void> disconnect(DisconnectParams params) async {}
}

void main() {
  group('DriveStore.messageFor', () {
    test('an unregistered build points to the set-up guide', () {
      for (final (code, detail) in [
        (
          GoogleSignInExceptionCode.unknownError,
          'SDK reported an exception: ApiException: 10: '
        ),
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

  group('DriveStore authorization', () {
    late _FakeGoogle google;
    setUp(() {
      google = _FakeGoogle();
      GoogleSignInPlatform.instance = google;
    });

    test(
        'names the remembered account, so a phone with two accounts still '
        'backs up without a prompt', () async {
      SharedPreferences.setMockInitialValues(
          {'drive_account_email': 'me@example.com'});
      google.granted = true;
      expect(await DriveStore().connectSilently(), isNotNull);
      expect(google.requests.single.email, 'me@example.com');
      expect(google.requests.single.promptIfUnauthorized, isFalse);
    });

    test('a silent request never prompts and reads as not connected', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await DriveStore().connectSilently(), isNull);
      expect(google.requests.map((r) => r.promptIfUnauthorized), [false]);
    });

    test('connect asks silently first, then prompts', () async {
      SharedPreferences.setMockInitialValues(
          {'drive_account_email': 'me@example.com'});
      await DriveStore().connect();
      expect(google.requests.map((r) => r.promptIfUnauthorized), [false, true]);
    });

    test('a refused prompt becomes a message, not a raw exception', () async {
      SharedPreferences.setMockInitialValues({});
      google.userAllows = false;
      expect(
          DriveStore().connect(),
          throwsA(isA<DriveBackupException>().having(
              (e) => e.message, 'message', 'Google sign-in was cancelled.')));
    });

    test('Switch account forgets the account, so the next backup asks',
        () async {
      SharedPreferences.setMockInitialValues(
          {'drive_account_email': 'me@example.com'});
      // No access left to revoke: only the local forgetting is exercised.
      await DriveStore().disconnect();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('drive_account_email'), isNull);
      expect(google.signOuts, 1);
    });
  });
}
