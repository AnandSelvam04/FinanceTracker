import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/settings_provider.dart';
import '../utils/app_logger.dart';
import 'auto_drive_backup.dart';
import 'backup/backup_errors.dart';
import 'backup/backup_payload.dart' as payload;
import 'backup/drive_store.dart';
import 'backup/local_files.dart' as files;
import 'backup_crypto.dart';
import 'db_service.dart';
import 'receipt_store.dart';
import 'secure_store.dart';

export 'auto_drive_backup.dart' show AutoDriveStatus;
export 'backup/backup_errors.dart';
export 'backup/csv_export.dart';

/// Local, encrypted and Google Drive backups, and restoring from any of them.
///
/// The pieces live under `backup/`: what a backup holds
/// (`backup_payload.dart`), the Drive connection and file
/// (`drive_store.dart`), the CSV downloads (`csv_export.dart`) and the
/// errors the screens catch (`backup_errors.dart`). This class ties them to
/// the files on the phone and the "when was this last backed up" stamps.
class BackupService {
  final DriveStore _drive = DriveStore();

  Future<String> get _localPath => files.documentsPath();

  static const _kLastBackup = 'last_backup_time';
  static const _kLastAutoBackup = 'last_auto_backup_time';

  /// When this device last wrote to (or restored from) the Drive copy. Kept
  /// apart from [_kLastBackup], which the daily on-device auto-backup also
  /// bumps: comparing Drive against that made a newer backup from another
  /// phone look older, so it was overwritten without the warning.
  static const _kLastDriveBackup = 'last_drive_backup_time';

  /// When a copy last left the phone (Drive, or a backup shared out). The
  /// on-device auto-backup dies with the phone, so it must not count towards
  /// the "you haven't backed up" nudge.
  static const _kLastOffDevice = 'last_off_device_backup_time';

  Future<File> get _backupFile async {
    final path = await _localPath;
    return File('$path/finance_backup.json');
  }

  Future<File> get _encryptedBackupFile async {
    final path = await _localPath;
    return File('$path/finance_backup_encrypted.json');
  }

  /// What the app held just before the last full restore, so that restore
  /// can be undone ([undoRestore]). Sealed with the device key when the
  /// database is encrypted, like the on-device backup.
  Future<File> get _preRestoreFile async {
    final path = await _localPath;
    return File('$path/pre_restore_backup.json');
  }

  /// The Drive stamp ([_kLastDriveBackup]) from before the last restore; a
  /// restore from Drive moves it, and undoing that restore puts it back so
  /// the next backup doesn't treat Drive's copy as this phone's own.
  static const _kPreRestoreDriveStamp = 'pre_restore_drive_stamp';

  /// How many days of local backups [backupHistory] keeps.
  ///
  /// The main local backup is replaced every day by the auto-backup, so on its
  /// own it can't undo a mistake: data deleted by accident (or wiped by a bad
  /// restore) was backed up — gone — on the next launch, over the last good
  /// copy. Keeping one copy per day for a week leaves time to notice.
  static const historyDays = 7;

  static const _historyDir = 'backup_history';
  static final _historyName =
      RegExp(r'^finance_backup_(\d{4})-(\d{2})-(\d{2})\.json$');

  Future<Directory> get _historyDirectory async =>
      Directory('${await _localPath}/$_historyDir');

  /// Writes [content] to [file] without ever leaving it half-written; see
  /// [files.writeAtomically].
  static Future<void> writeAtomically(File file, String content) =>
      files.writeAtomically(file, content);

  /// Copies the backup just written to [source] into today's slot of the
  /// history, then drops all but the newest [historyDays] days. Failures are
  /// logged, not thrown: the main backup has already been written.
  Future<void> _keepInHistory(File source, DateTime now) async {
    try {
      final dir = await _historyDirectory;
      await dir.create(recursive: true);
      final day = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      await writeAtomically(File('${dir.path}/finance_backup_$day.json'),
          await source.readAsString());
      final entries = await backupHistory();
      for (final old in entries.skip(historyDays)) {
        await old.file.delete();
      }
    } catch (e, s) {
      AppLogger.error('Keeping a dated copy of the backup failed', e, s);
    }
  }

  /// The dated local backups kept by [backupToJson], newest first — one per
  /// day for the last [historyDays] days a backup was taken. Each can be
  /// restored with [restoreFromFile].
  Future<List<({DateTime day, File file})>> backupHistory() async {
    final dir = await _historyDirectory;
    if (!await dir.exists()) return const [];
    final out = <({DateTime day, File file})>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final m = _historyName.firstMatch(entity.uri.pathSegments.last);
      if (m == null) continue;
      out.add((
        day: DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!),
            int.parse(m.group(3)!)),
        file: entity,
      ));
    }
    out.sort((a, b) => b.day.compareTo(a.day));
    return out;
  }

  /// When the most recent backup (local, auto, or Drive) was taken.
  Future<DateTime?> lastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastBackup);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// When a backup last left the phone: to Drive, or shared out of the app.
  /// Null when every backup so far lives only on this device.
  Future<DateTime?> lastOffDeviceBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastOffDevice);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> _markBackedUp({bool offDevice = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toIso8601String();
    await prefs.setString(_kLastBackup, now);
    if (offDevice) await prefs.setString(_kLastOffDevice, now);
  }

  /// Records that a full backup was shared out of the app (saved to Files,
  /// emailed, …), so it counts as a copy that survives losing the phone.
  Future<void> markSharedOffDevice() => _markBackedUp(offDevice: true);

  /// Writes a local backup at most once per [minInterval] to protect against
  /// data loss when users forget to back up manually. Safe to call on launch.
  /// When at-rest database encryption is enabled, the backup is encrypted
  /// with the same device-held key so it doesn't leave a readable copy of
  /// the data on disk.
  Future<bool> autoBackupIfDue(
      {Duration minInterval = const Duration(days: 1)}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastAutoBackup);
    final last = raw == null ? null : DateTime.tryParse(raw);
    if (last != null && DateTime.now().difference(last) < minInterval) {
      return false;
    }
    // This runs unguarded during launch, so it must not throw. If the device
    // key is unavailable while encryption is on, skip the backup rather than
    // fall back to writing a plaintext copy of everything.
    final String? deviceKey;
    try {
      deviceKey = await DBService().deviceKeyIfEncrypted();
    } catch (e) {
      AppLogger.error(
          'Skipping auto-backup: database encryption is on but its key could '
          'not be read, and an unencrypted backup would defeat it',
          e);
      return false;
    }
    try {
      await backupToJson(deviceKey: deviceKey);
    } catch (e, st) {
      // A full disk or unwritable file used to escape here and abort the rest
      // of the launch sequence, so bill and budget reminders were never
      // scheduled. Log it; the next launch tries again.
      AppLogger.error('Auto-backup failed', e, st);
      return false;
    }
    await prefs.setString(_kLastAutoBackup, DateTime.now().toIso8601String());
    return true;
  }

  /// Writes the full-data JSON backup and returns the file so it can be
  /// shared/downloaded by the user.
  ///
  /// When at-rest database encryption is on the file is written as an
  /// encrypted envelope, exactly like the auto-backup — otherwise this path
  /// would drop a readable copy of every transaction on disk (and hand it to
  /// the share sheet) the moment the user tapped "Backup locally". Use
  /// [writeEncryptedBackup] for a copy that can be restored on another device.
  Future<File> writeJsonBackupFile() async {
    await backupToJson(deviceKey: await DBService().deviceKeyIfEncrypted());
    return _backupFile;
  }

  /// Writes the full-data backup to the local backup file — plaintext, or as
  /// an encrypted envelope when [deviceKey] is given (used by the auto-backup
  /// when at-rest database encryption is on).
  ///
  /// A copy is also kept under today's date in [backupHistory] ([now] stands
  /// in for the clock in tests).
  Future<void> backupToJson({String? deviceKey, DateTime? now}) async {
    var content = jsonEncode(await payload.collectBackupData());
    if (deviceKey != null) {
      content = await BackupCrypto.encryptString(content, deviceKey);
    }
    final file = await _backupFile;
    await writeAtomically(file, content);
    await _keepInHistory(file, now ?? DateTime.now());
    await _markBackedUp();
  }

  /// Writes a passphrase-encrypted full-data backup and returns the file so it
  /// can be shared. The passphrase is not stored anywhere.
  Future<File> writeEncryptedBackup(String passphrase) async {
    final envelope = await BackupCrypto.encryptString(
        jsonEncode(await payload.collectBackupData()), passphrase);
    final file = await _encryptedBackupFile;
    await writeAtomically(file, envelope);
    await _markBackedUp();
    return file;
  }

  /// Restores from the local encrypted backup. Throws on a wrong passphrase or
  /// corrupt/missing file.
  Future<void> restoreFromEncryptedFile(String passphrase,
      {bool clearBeforeRestore = true, bool allowEmpty = false}) async {
    final file = await _encryptedBackupFile;
    if (!await file.exists()) {
      throw Exception('No encrypted backup found on this device');
    }
    final envelope = await file.readAsString();
    final plain = await BackupCrypto.decryptString(envelope, passphrase);
    await _applyRestore(jsonDecode(plain),
        clearBeforeRestore: clearBeforeRestore, allowEmpty: allowEmpty);
  }

  /// Turns a backup file's contents into its payload; see
  /// [payload.decodeBackupContent].
  static Future<dynamic> decodeBackupContent(String content,
          {String? deviceKey, String? passphrase}) =>
      payload.decodeBackupContent(content,
          deviceKey: deviceKey, passphrase: passphrase);

  Future<dynamic> _decode(String content, {String? passphrase}) async {
    String? deviceKey;
    try {
      deviceKey = await DBService().deviceKeyIfEncrypted();
    } catch (e) {
      AppLogger.error('Device key unavailable while opening a backup', e);
    }
    return decodeBackupContent(content,
        deviceKey: deviceKey, passphrase: passphrase);
  }

  /// Restores from a backup file the user picked (a download, a copy from
  /// another phone, an emailed backup). Plain or encrypted; throws
  /// [PassphraseRequiredException] when it needs a passphrase.
  Future<void> restoreFromFile(String path,
      {String? passphrase, bool allowEmpty = false}) async {
    final content = await File(path).readAsString();
    final data = await _decode(content, passphrase: passphrase);
    await _applyRestore(data, clearBeforeRestore: true, allowEmpty: allowEmpty);
  }

  Future<void> restoreFromJson(
      {bool clearBeforeRestore = true,
      String? deviceKey,
      bool allowEmpty = false}) async {
    final file = await _backupFile;
    if (!await file.exists()) return;
    var content = await file.readAsString();
    // Auto-backups taken while database encryption is on are stored as an
    // encrypted envelope; decrypt with the same device-held key.
    if (BackupCrypto.isEncrypted(content)) {
      deviceKey ??= await DBService().deviceKeyIfEncrypted();
      if (deviceKey == null) {
        throw Exception(
            'This backup is encrypted with the device key, which is no '
            'longer available. Enable database encryption or use a '
            'passphrase-encrypted backup instead.');
      }
      content = await BackupCrypto.decryptString(content, deviceKey);
    }
    await _applyRestore(jsonDecode(content),
        clearBeforeRestore: clearBeforeRestore, allowEmpty: allowEmpty);
  }

  /// Validates the backup payload, converts it to row maps, and applies it in
  /// one database transaction: a malformed backup or an interruption rolls
  /// back, leaving the existing data untouched.
  ///
  /// Set [allowEmpty] only after the user has confirmed they really mean to
  /// replace their data with an empty backup.
  Future<void> _applyRestore(Object? raw,
      {bool clearBeforeRestore = true,
      bool allowEmpty = false,
      bool keepUndo = true}) async {
    final data = payload.validateBackupPayload(raw);

    if (clearBeforeRestore &&
        !allowEmpty &&
        payload.backupRowCount(data) == 0) {
      throw EmptyBackupException(
          'That backup contains no transactions, accounts, or budgets. '
          'Restoring it would erase everything currently in the app.');
    }

    final rowsByTable = payload.rowsFromBackup(data);

    // A full restore replaces everything, and the on-device backup is then
    // rewritten from the restored data — so keep what is here now, to undo
    // it with. Done after the backup has been checked, so a backup that is
    // refused leaves the previous undo copy alone.
    if (clearBeforeRestore && keepUndo) await _keepForUndo();
    int rows(String key) => (data[key] as List?)?.length ?? 0;
    lastRestoreCounts =
        (transactions: rows('expenses'), accounts: rows('accounts'));

    await DBService()
        .replaceAllData(rowsByTable, clearFirst: clearBeforeRestore);
    // Settings only come back with a full restore; merging a backup into
    // existing data keeps this phone's own. Older backups carry none.
    final settings = data['settings'];
    if (clearBeforeRestore && settings is Map) {
      await SettingsProvider.importFromBackup(settings);
    }
    // Backups hold a receipt photo's path, not the image. Where the image
    // isn't on this phone (a new phone, a reinstall), take the mark off the
    // transaction instead of leaving a paperclip that opens to nothing. The
    // restore itself has succeeded, so a failure here is only logged.
    try {
      missingReceiptPhotos = await ReceiptStore.forgetMissing();
    } catch (e, st) {
      AppLogger.error(
          'Could not check receipt photos after the restore', e, st);
    }
  }

  /// Saves the app's current data as [_preRestoreFile]. Nothing worth
  /// keeping (a fresh install) clears it instead, so there is no Undo that
  /// would only empty the app again.
  Future<void> _keepForUndo() async {
    final file = await _preRestoreFile;
    final current = await payload.collectBackupData();
    if (payload.backupRowCount(payload.validateBackupPayload(current)) == 0) {
      if (await file.exists()) await file.delete();
      return;
    }
    var content = jsonEncode(current);
    final deviceKey = await DBService().deviceKeyIfEncrypted();
    if (deviceKey != null) {
      content = await BackupCrypto.encryptString(content, deviceKey);
    }
    await writeAtomically(file, content);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kPreRestoreDriveStamp, prefs.getString(_kLastDriveBackup) ?? '');
  }

  /// Deletes every transaction, account, budget, investment, goal and rule
  /// (settings stay). What was there is kept first, so [undoRestore] can
  /// put it back.
  Future<void> eraseAllData() async {
    await _keepForUndo();
    await DBService().replaceAllData(const {}, clearFirst: true);
  }

  /// Whether the last restore can be undone ([undoRestore]).
  Future<bool> canUndoRestore() async => (await _preRestoreFile).exists();

  /// Puts back what the app held before the last full restore, and the
  /// on-device backup with it. The undo copy is used up.
  Future<void> undoRestore() async {
    final file = await _preRestoreFile;
    if (!await file.exists()) {
      throw Exception('There is no restore to undo');
    }
    final data = await _decode(await file.readAsString());
    await _applyRestore(data,
        clearBeforeRestore: true, allowEmpty: true, keepUndo: false);
    await backupToJson(deviceKey: await DBService().deviceKeyIfEncrypted());
    final prefs = await SharedPreferences.getInstance();
    final stamp = prefs.getString(_kPreRestoreDriveStamp);
    if (stamp == null || stamp.isEmpty) {
      await prefs.remove(_kLastDriveBackup);
    } else {
      await prefs.setString(_kLastDriveBackup, stamp);
    }
    await prefs.remove(_kPreRestoreDriveStamp);
    await file.delete();
  }

  /// What the last restore brought in, for the screen to say so.
  ({int transactions, int accounts})? lastRestoreCounts;

  /// How many transactions in the last restore had a receipt photo that is
  /// not on this device, so the screen can say they came back without one.
  int missingReceiptPhotos = 0;

  /// Checks that the local backup file is actually restorable — it exists,
  /// decrypts (if it's a device-key envelope), has a valid shape, and every
  /// row parses through its model — without touching the live database. This
  /// turns "a backup exists" into "a backup that would actually restore".
  Future<BackupVerification> verifyLocalBackup() async {
    try {
      final file = await _backupFile;
      if (!await file.exists()) {
        return BackupVerification.failure(
            'No local backup found yet. Tap "Backup locally" first.');
      }
      var content = await file.readAsString();
      if (BackupCrypto.isEncrypted(content)) {
        final deviceKey = await DBService().deviceKeyIfEncrypted();
        if (deviceKey == null) {
          return BackupVerification.failure(
              'The backup is encrypted with this device\'s key, which isn\'t '
              'available, so it can\'t be verified here.');
        }
        content = await BackupCrypto.decryptString(content, deviceKey);
      }
      final data = payload.validateBackupPayload(jsonDecode(content));
      // Parsing every row is the real test: a corrupt value throws here.
      final rows = payload.rowsFromBackup(data);
      final counts = {
        for (final e in rows.entries) e.key: e.value.length,
      };
      return BackupVerification.success(counts);
    } catch (e) {
      return BackupVerification.failure('$e');
    }
  }

  // --- Google Drive --------------------------------------------------------

  /// The Google account Drive backups go to, resolved silently (no prompt),
  /// or null when Drive access hasn't been given / isn't set up. Used to
  /// show "Backed up as you@gmail.com" without asking.
  Future<String?> currentDriveAccountEmail() => _drive.accountEmail();

  /// Takes back this phone's Drive access so the next backup/restore asks
  /// for an account — lets the user switch which Google account it uses.
  Future<void> signOutDrive() => _drive.disconnect();

  /// Uploads a full backup to Drive, sealed with [passphrase] when given.
  ///
  /// With database encryption on a passphrase is required. The Drive copy
  /// used to be sealed with this device's key instead — but that key lives
  /// only on this phone, so the one backup meant to survive losing the phone
  /// could only be opened *on* that phone.
  ///
  /// When automatic Drive backup is on, [passphrase] also becomes the one it
  /// seals with, so the Drive copy never switches between two passphrases.
  Future<void> backupToDrive({String? passphrase}) async {
    if (passphrase == null && await DBService().isEncryptionEnabled()) {
      throw DriveBackupException(
          'Database encryption is on, so the Drive backup needs a '
          'passphrase to protect it.');
    }
    await _backupToDriveWith(await _drive.connect(), passphrase);
    await _clearAutoDriveProblem();
    if (passphrase != null && await AutoDriveBackup.isOn()) {
      try {
        await _secureStorage.write(
            key: _kAutoDrivePassphrase, value: passphrase);
      } catch (e) {
        // The backup itself succeeded; the automatic one keeps the old
        // passphrase until the next manual backup.
        AppLogger.error('Could not store the automatic backup passphrase', e);
      }
    }
  }

  // --- Automatic Drive backup ---------------------------------------------

  static const FlutterSecureStorage _secureStorage = appSecureStorage;

  /// The passphrase the automatic Drive backup seals with. Kept in the
  /// device keystore, next to the database key, never in plain preferences.
  static const _kAutoDrivePassphrase = 'auto_drive_backup_passphrase';

  /// When this phone last wrote to (or restored from) the Drive copy.
  Future<DateTime?> lastDriveBackupTime() async {
    final raw =
        (await SharedPreferences.getInstance()).getString(_kLastDriveBackup);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<bool> isAutoDriveBackupOn() => AutoDriveBackup.isOn();

  Future<AutoDriveStatus?> lastAutoDriveStatus() =>
      AutoDriveBackup.lastStatus();

  /// Switches automatic Drive backup on. Asks for Drive access first (this
  /// may show the account picker), so later backups can run without a
  /// prompt. [passphrase] seals the Drive copy; it is required while
  /// database encryption is on.
  Future<void> enableAutoDriveBackup({String? passphrase}) async {
    if (passphrase == null && await DBService().readEncryptionFlagOrThrow()) {
      throw DriveBackupException(
          'Database encryption is on, so automatic Drive backups need a '
          'passphrase to protect them.');
    }
    await _drive.connect();
    if (passphrase != null) await setAutoDrivePassphrase(passphrase);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AutoDriveBackup.kEnabled, true);
    // A fresh start: an old attempt must not delay the first backup.
    await prefs.remove(AutoDriveBackup.kLastAttempt);
    await prefs.remove(AutoDriveBackup.kStatus);
  }

  /// Switches automatic Drive backup off and forgets its passphrase.
  Future<void> disableAutoDriveBackup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AutoDriveBackup.kEnabled, false);
    await prefs.remove(AutoDriveBackup.kStatus);
    try {
      await _secureStorage.delete(key: _kAutoDrivePassphrase);
    } catch (e) {
      AppLogger.error('Could not remove the automatic backup passphrase', e);
    }
  }

  /// After a manual backup or a restore the Drive copy and this phone agree,
  /// so whatever held up the automatic backup (another phone's newer copy,
  /// not signed in) no longer applies. Clearing it lets the next launch try
  /// again instead of waiting out [AutoDriveBackup.retryAfter].
  Future<void> _clearAutoDriveProblem() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AutoDriveBackup.kStatus);
    await prefs.remove(AutoDriveBackup.kLastAttempt);
  }

  Future<void> setAutoDrivePassphrase(String passphrase) =>
      _secureStorage.write(key: _kAutoDrivePassphrase, value: passphrase);

  /// Backs up to Drive if automatic backup is on and one is due. Never
  /// prompts and never throws; safe to call on every launch.
  Future<AutoDriveStatus> autoDriveBackupIfDue({bool force = false}) {
    drive.DriveApi? api;
    return AutoDriveBackup(
      lastDriveBackup: lastDriveBackupTime,
      isEncrypted: DBService().readEncryptionFlagOrThrow,
      readPassphrase: () => _secureStorage.read(key: _kAutoDrivePassphrase),
      isSignedIn: () async => (api = await _drive.connectSilently()) != null,
      remoteIsNewer: () => _remoteNewerThanThisPhone(api!, strict: true),
      upload: (passphrase) => _backupToDriveWith(api!, passphrase),
    ).run(force: force);
  }

  Future<void> _backupToDriveWith(
      drive.DriveApi driveApi, String? passphrase) async {
    var content = jsonEncode(await payload.collectBackupData());
    if (passphrase != null) {
      content = await BackupCrypto.encryptString(content, passphrase);
    }
    // Its own file: writing the upload over _backupFile replaced the
    // on-device auto-backup with a copy this phone may not be able to open.
    final file = File('${await _localPath}/finance_backup_drive.json');
    await file.writeAsString(content);
    final DateTime? modified;
    try {
      modified = await DriveStore.upload(driveApi, file);
    } finally {
      try {
        await file.delete();
      } catch (e) {
        AppLogger.error('Failed to clean up the Drive upload file', e);
      }
    }

    await _markBackedUp(offDevice: true);
    await _markInStepWithDrive(modified);
  }

  /// Records that this phone and the Drive copy now agree, as of
  /// [driveModified] — the time Drive itself stamped on the file.
  ///
  /// [_remoteNewerThanThisPhone] compares this against Drive's modified time,
  /// so it has to come from the same clock. Stamping the phone's own time
  /// meant a phone running even a few seconds slow saw its own upload as a
  /// newer copy from another phone: the automatic backup then refused to
  /// overwrite it, and the manual one warned every time. The phone's clock is
  /// only the fallback when Drive doesn't report a time.
  static Future<void> _markInStepWithDrive(DateTime? driveModified) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastDriveBackup,
        driveStamp(driveModified, DateTime.now()).toIso8601String());
  }

  /// The time to remember for a Drive copy last modified at [driveModified],
  /// in local time like the other backup stamps.
  static DateTime driveStamp(DateTime? driveModified, DateTime now) =>
      (driveModified ?? now).toLocal();

  /// Whether the Drive copy was written after this device last backed up to
  /// (or restored from) Drive — i.e. by another phone, so overwriting it
  /// would lose that phone's data.
  ///
  /// When the check fails this answers false, so the manual backup isn't
  /// blocked; the automatic one uses [_remoteNewerThanThisPhone], which
  /// throws instead and so skips the upload.
  Future<bool> isRemoteBackupNewer() async {
    try {
      return await _remoteNewerThanThisPhone(await _drive.connect());
    } catch (e) {
      // If we can't check, assume false to avoid blocking the user,
      // but log the error.
      AppLogger.error('Error checking remote backup', e);
      return false;
    }
  }

  /// [strict] is for the automatic backup: it ignores the fallback to the
  /// general backup time, which the daily on-device backup keeps bumping. A
  /// phone that has never written to Drive then treats an existing Drive copy
  /// as another phone's, instead of overwriting, say, the old phone's backup
  /// on a new phone that was set up without restoring it.
  Future<bool> _remoteNewerThanThisPhone(drive.DriveApi driveApi,
      {bool strict = false}) async {
    final remote = await DriveStore.newestBackup(driveApi);
    final remoteModified = remote?.modified;
    if (remoteModified == null) return false; // No (dated) remote backup.

    final prefs = await SharedPreferences.getInstance();
    // Before the Drive time was kept separately, the Drive backup only
    // stamped the shared one; fall back to it until the next Drive backup.
    final lastBackupStr = prefs.getString(_kLastDriveBackup) ??
        (strict ? null : prefs.getString(_kLastBackup));

    if (lastBackupStr == null) {
      // We have never backed up from this device, but a remote file exists.
      // Remote is definitely "newer" (or at least unknown).
      return true;
    }

    final lastLocalBackupTime = DateTime.parse(lastBackupStr);
    // Drive returns UTC time
    return remoteModified.isAfter(lastLocalBackupTime);
  }

  /// Restores the Drive copy. Throws [PassphraseRequiredException] when it
  /// is passphrase-protected and [passphrase] is missing or wrong.
  Future<void> restoreFromDrive(
      {bool allowEmpty = false, String? passphrase}) async {
    final driveApi = await _drive.connect();
    final remote = await DriveStore.newestBackup(driveApi);
    if (remote == null) throw Exception('No Drive backup found');

    // Download to a temp file first. Streaming straight over _backupFile
    // destroyed the user's local safety-net backup before we knew the remote
    // payload was even usable — a truncated download then left them with
    // neither. Validate first.
    final target = await _backupFile;
    final temp = File('${target.path}.download');
    try {
      await DriveStore.download(driveApi, remote.id, temp);

      // Parse (and decrypt) before anything is touched, so a corrupt
      // download fails harmlessly. Older Drive copies are sealed with the
      // device key; newer ones with a passphrase.
      final data = payload.validateBackupPayload(
          await _decode(await temp.readAsString(), passphrase: passphrase));

      // Restore first, then refresh the on-device backup from the restored
      // data. If the restore throws — corrupt rows, or an unconfirmed empty
      // backup — the local backup is still the user's own last good copy.
      await _applyRestore(data,
          clearBeforeRestore: true, allowEmpty: allowEmpty);
      await backupToJson(deviceKey: await DBService().deviceKeyIfEncrypted());
      // This device now matches the Drive copy: backing up again straight
      // away is not overwriting someone else's newer data.
      await _markInStepWithDrive(remote.modified);
      await _clearAutoDriveProblem();
    } finally {
      if (await temp.exists()) {
        try {
          await temp.delete();
        } catch (e) {
          AppLogger.error('Failed to clean up partial Drive download', e);
        }
      }
    }
  }
}
