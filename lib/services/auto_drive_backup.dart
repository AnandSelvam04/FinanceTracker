import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';

/// What the last automatic Drive backup attempt did.
enum AutoDriveStatus {
  /// Uploaded.
  done,

  /// Automatic Drive backup is switched off.
  off,

  /// Not attempted: backed up recently enough, or tried a short while ago.
  notDue,

  /// No Google account is signed in on this phone. The automatic backup never
  /// shows a sign-in prompt, so it waits for a manual backup to sign in.
  notSignedIn,

  /// Database encryption is on but no passphrase is stored for the Drive
  /// copy, and an automatic backup can't ask for one.
  needsPassphrase,

  /// The Drive copy was written by another phone after this one last backed
  /// up. Overwriting it could lose that phone's data, so the user decides.
  remoteNewer,

  /// Something went wrong (offline, Drive error). Retried later.
  failed,
}

/// Decides whether, and how, to back up to Google Drive without the user
/// asking. The Drive and sign-in work is passed in, so this policy can be
/// tested without a network or a Google account.
///
/// It never throws, never prompts, and errs towards not uploading: when it
/// can't tell whether the Drive copy came from another phone, it skips.
class AutoDriveBackup {
  AutoDriveBackup({
    required this.lastDriveBackup,
    required this.isEncrypted,
    required this.readPassphrase,
    required this.isSignedIn,
    required this.remoteIsNewer,
    required this.upload,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// When this phone last wrote to (or restored from) Drive.
  final Future<DateTime?> Function() lastDriveBackup;

  /// Whether database encryption is on. Should throw when it can't tell, so
  /// an unknown state never leads to a plaintext upload.
  final Future<bool> Function() isEncrypted;

  /// The stored passphrase for the Drive copy, or null.
  final Future<String?> Function() readPassphrase;

  /// Whether a Google account is signed in, checked without prompting.
  final Future<bool> Function() isSignedIn;

  /// Whether another phone wrote the Drive copy since this one last did.
  /// Should throw when it can't check.
  final Future<bool> Function() remoteIsNewer;

  /// Uploads a full backup, sealed with the passphrase when given.
  final Future<void> Function(String? passphrase) upload;

  final DateTime Function() _now;

  static const kEnabled = 'auto_drive_backup_enabled';
  static const kLastAttempt = 'auto_drive_last_attempt';
  static const kStatus = 'auto_drive_status';

  /// How often to back up.
  static const interval = Duration(days: 1);

  /// How long to wait after an attempt that didn't upload (offline, not signed
  /// in, a newer copy from another phone) before trying again. Without it,
  /// every launch while offline would wait on the network.
  static const retryAfter = Duration(hours: 6);

  static Future<bool> isOn() async =>
      (await SharedPreferences.getInstance()).getBool(kEnabled) ?? false;

  static Future<AutoDriveStatus?> lastStatus() async {
    final name = (await SharedPreferences.getInstance()).getString(kStatus);
    for (final s in AutoDriveStatus.values) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// Backs up if automatic Drive backup is on and a backup is due. [force]
  /// skips the timing checks (used right after switching it on).
  ///
  /// [every] replaces [interval] for this run: the app passes a shorter one
  /// when it is put away with changes made since the last backup, so they
  /// don't wait for tomorrow's launch to leave the phone.
  Future<AutoDriveStatus> run({bool force = false, Duration? every}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(kEnabled) ?? false)) return AutoDriveStatus.off;
    final now = _now();
    if (!force) {
      try {
        final last = await lastDriveBackup();
        if (last != null && now.difference(last) < (every ?? interval)) {
          return AutoDriveStatus.notDue;
        }
      } catch (e) {
        AppLogger.error('Could not read the last Drive backup time', e);
      }
      final tried = DateTime.tryParse(prefs.getString(kLastAttempt) ?? '');
      if (tried != null && now.difference(tried) < retryAfter) {
        return AutoDriveStatus.notDue;
      }
    }
    await prefs.setString(kLastAttempt, now.toIso8601String());
    final status = await _attempt();
    await prefs.setString(kStatus, status.name);
    return status;
  }

  Future<AutoDriveStatus> _attempt() async {
    try {
      final passphrase = await readPassphrase();
      if (passphrase == null && await isEncrypted()) {
        return AutoDriveStatus.needsPassphrase;
      }
      if (!await isSignedIn()) return AutoDriveStatus.notSignedIn;
      if (await remoteIsNewer()) return AutoDriveStatus.remoteNewer;
      await upload(passphrase);
      return AutoDriveStatus.done;
    } catch (e, st) {
      AppLogger.error('Automatic Drive backup failed', e, st);
      return AutoDriveStatus.failed;
    }
  }
}
