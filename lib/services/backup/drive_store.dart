/// Google Drive access for the backups: getting permission to use Drive, and
/// reading and writing the one backup file in the app's hidden Drive folder.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_logger.dart';
import 'backup_errors.dart';

/// Permission to use Drive, and the backup file kept there.
///
/// Only *authorization* is used — permission for the two Drive scopes — never
/// Google's sign-in (authentication). Since google_sign_in 7, sign-in on
/// Android goes through Credential Manager and needs a *web* OAuth client id,
/// which this app has never registered. Authorization goes through Android's
/// AuthorizationClient instead, which matches the existing Android OAuth
/// client on package name + signing SHA-1, so the set-up in
/// docs/GOOGLE_DRIVE_SETUP.md keeps working unchanged.
///
/// Without a sign-in there is no account object, so the email shown on the
/// Backups screen comes from Drive itself (`about.get`) and is remembered.
class DriveStore {
  static const scopes = [
    drive.DriveApi.driveFileScope,
    drive.DriveApi.driveAppdataScope,
  ];

  /// The backup's name in the app-data folder.
  static const backupName = 'finance_backup.json';

  static const _kAccountEmail = 'drive_account_email';

  static Future<void>? _initialized;

  /// [GoogleSignIn.initialize] must run exactly once before any other call.
  static Future<void> _ensureInitialized() => _initialized ??=
          GoogleSignIn.instance.initialize().catchError((Object e) {
        // Let a later call try again rather than fail for the app's lifetime.
        _initialized = null;
        throw e;
      });

  static GoogleSignInAuthorizationClient get _auth =>
      GoogleSignIn.instance.authorizationClient;

  /// A Drive client, asking the user to choose an account and allow Drive
  /// access when this phone has not been given it yet.
  Future<drive.DriveApi> connect() async {
    try {
      await _ensureInitialized();
      final authz = await _auth.authorizationForScopes(scopes) ??
          await _auth.authorizeScopes(scopes);
      return _clientFor(authz.accessToken);
    } on GoogleSignInException catch (e) {
      throw DriveBackupException(messageFor(e.code, e.description));
    } on PlatformException catch (e) {
      throw DriveBackupException(messageFor(null, '${e.code} ${e.message}'));
    }
  }

  /// A Drive client for the access already given on this phone, or null
  /// when there is none. Never shows a prompt. A failure (offline) throws
  /// rather than reading as "not connected".
  Future<drive.DriveApi?> connectSilently() async {
    await _ensureInitialized();
    final authz = await _auth.authorizationForScopes(scopes);
    return authz == null ? null : _clientFor(authz.accessToken);
  }

  /// The Google account the backups go to, without prompting, or null when
  /// Drive access hasn't been given (or can't be checked right now).
  Future<String?> accountEmail() async {
    try {
      final api = await connectSilently();
      final prefs = await SharedPreferences.getInstance();
      if (api == null) {
        await prefs.remove(_kAccountEmail);
        return null;
      }
      final known = prefs.getString(_kAccountEmail);
      if (known != null) return known;
      final about = await api.about.get($fields: 'user(emailAddress)');
      final email = about.user?.emailAddress;
      if (email != null) await prefs.setString(_kAccountEmail, email);
      return email;
    } catch (e) {
      // No cached access, offline, Drive not set up: for display purposes
      // all of these just mean "not connected".
      AppLogger.error('Could not resolve the Drive account', e);
      return null;
    }
  }

  /// Takes back the Drive access given on this phone, so the next backup
  /// asks which account to use.
  ///
  /// Signing out alone no longer does that: it clears the sign-in, but the
  /// Drive authorization outlives it and would quietly pick the same account
  /// again. Revoking the grant is what makes the account picker show.
  Future<void> disconnect() async {
    try {
      await _ensureInitialized();
      final authz = await _auth.authorizationForScopes(scopes);
      if (authz != null) {
        final token = authz.accessToken;
        final response = await http.post(
          Uri.parse('https://oauth2.googleapis.com/revoke'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'token': token},
        );
        if (response.statusCode != 200) {
          AppLogger.error(
              'Revoking Drive access answered ${response.statusCode}');
        }
        await _auth.clearAuthorizationToken(accessToken: token);
      }
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      AppLogger.error('Disconnecting from Drive failed', e);
    }
    try {
      await (await SharedPreferences.getInstance()).remove(_kAccountEmail);
    } catch (e) {
      AppLogger.error('Could not forget the Drive account', e);
    }
  }

  static drive.DriveApi _clientFor(String accessToken) =>
      drive.DriveApi(_AuthClient({'Authorization': 'Bearer $accessToken'}));

  /// Translates a Google failure into a message the user can act on.
  ///
  /// The most common one is `ApiException: 10` (DEVELOPER_ERROR): the build
  /// has no OAuth client registered for this package name + signing SHA-1,
  /// so Google refuses. That's a one-time build/Cloud setup — it can't be
  /// fixed on the device — so the user is steered to the local backups,
  /// which always work.
  @visibleForTesting
  static String messageFor(GoogleSignInExceptionCode? code, String? detail) {
    final text = (detail ?? '').toLowerCase();
    if (text.contains('apiexception: 10') ||
        text.contains('developer_error') ||
        code == GoogleSignInExceptionCode.clientConfigurationError ||
        code == GoogleSignInExceptionCode.providerConfigurationError) {
      return 'Google Drive backup is not set up for this build, so Google '
          'rejected the sign-in. Your data is safe — use "Backup locally '
          '(JSON)" or the encrypted backup below instead. (Enabling Drive '
          'needs a one-time Google Cloud sign-in setup; see '
          'docs/GOOGLE_DRIVE_SETUP.md.)';
    }
    if (text.contains('network')) {
      return 'Could not reach Google to sign in. Check your connection and '
          'try again, or use a local/encrypted backup below.';
    }
    if (code == GoogleSignInExceptionCode.canceled) {
      return 'Google sign-in was cancelled.';
    }
    return 'Google sign-in failed (${code?.name ?? detail}). Your data is '
        'safe — use a local or encrypted backup below.';
  }

  // --- The backup file ----------------------------------------------------

  /// The newest backup in the app-data folder, or null when there is none.
  static Future<({String id, DateTime? modified})?> newestBackup(
      drive.DriveApi api) async {
    final list = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$backupName' and trashed = false",
      orderBy: 'modifiedTime desc',
      pageSize: 1,
      $fields: 'files(id, modifiedTime)',
    );
    final newest = list.files?.firstOrNull;
    final id = newest?.id;
    if (newest == null || id == null) return null;
    return (id: id, modified: newest.modifiedTime);
  }

  /// Uploads [file] as the Drive copy and returns the modified time Drive
  /// gave it.
  ///
  /// Updates the existing Drive copy in place (instead of creating a new
  /// file on every backup, which used to pile up copies in the app-data
  /// folder forever). Any stale duplicates from old versions are removed
  /// after a successful upload.
  static Future<DateTime?> upload(drive.DriveApi api, File file) async {
    final length = await file.length();
    final existing = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$backupName' and trashed = false",
      orderBy: 'modifiedTime desc',
      $fields: 'files(id)',
    );
    final existingFiles = existing.files ?? const <drive.File>[];

    if (existingFiles.isEmpty) {
      final created = await api.files.create(
        drive.File()
          ..name = backupName
          ..parents = ['appDataFolder'],
        uploadMedia: drive.Media(file.openRead(), length),
        $fields: 'id, modifiedTime',
      );
      return created.modifiedTime;
    }
    final updated = await api.files.update(
      drive.File()..name = backupName,
      existingFiles.first.id!,
      uploadMedia: drive.Media(file.openRead(), length),
      $fields: 'id, modifiedTime',
    );
    for (final stale in existingFiles.skip(1)) {
      final id = stale.id;
      if (id == null) continue;
      try {
        await api.files.delete(id);
      } catch (e) {
        AppLogger.error('Failed to delete stale Drive backup', e);
      }
    }
    return updated.modifiedTime;
  }

  /// Downloads the Drive file [id] into [target].
  static Future<void> download(
      drive.DriveApi api, String id, File target) async {
    final media = await api.files.get(
      id,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final sink = target.openWrite();
    await media.stream.pipe(sink);
    await sink.flush();
    await sink.close();
  }
}

class _AuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _AuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _client.send(request..headers.addAll(_headers));
}
