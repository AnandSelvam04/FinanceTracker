import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
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
            e.description,
            // Export human-readable major units (e.g. 120.50).
            minorToMajor(e.amount).toStringAsFixed(2),
            e.date.toIso8601String(),
            e.category,
            e.paymentMode,
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
          i.name,
          minorToMajor(i.amount).toStringAsFixed(2),
          i.date.toIso8601String(),
          i.type,
        ]),
  ];
  String csvData = const ListToCsvConverter().convert(rows);
  final backupService = BackupService();
  final path = await backupService._localPath;
  final file = File('$path/investments_export.csv');
  await file.writeAsString(csvData);
  return file;
}

class BackupService {
  final gsi.GoogleSignIn _googleSignIn = gsi.GoogleSignIn(
    scopes: [
      drive.DriveApi.driveFileScope,
      drive.DriveApi.driveAppdataScope,
    ],
  );

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
    await backupToJson(deviceKey: await DBService().deviceKeyIfEncrypted());
    await prefs.setString(
        _kLastAutoBackup, DateTime.now().toIso8601String());
    return true;
  }

  /// Writes the full-data JSON backup and returns the file so it can be
  /// shared/downloaded by the user.
  Future<File> writeJsonBackupFile() async {
    await backupToJson();
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
      {bool clearBeforeRestore = true}) async {
    final file = await _encryptedBackupFile;
    if (!await file.exists()) {
      throw Exception('No encrypted backup found on this device');
    }
    final envelope = await file.readAsString();
    final plain = await BackupCrypto.decryptString(envelope, passphrase);
    await _applyRestore(jsonDecode(plain),
        clearBeforeRestore: clearBeforeRestore);
  }

  Future<void> restoreFromJson(
      {bool clearBeforeRestore = true, String? deviceKey}) async {
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
        clearBeforeRestore: clearBeforeRestore);
  }

  /// Validates the backup payload, converts it to row maps, and applies it in
  /// one database transaction: a malformed backup or an interruption rolls
  /// back, leaving the existing data untouched.
  Future<void> _applyRestore(dynamic data,
      {bool clearBeforeRestore = true}) async {
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
    final account =
        await _googleSignIn.signInSilently() ?? await _googleSignIn.signIn();
    if (account == null) {
      throw Exception('Google sign-in was cancelled');
    }
    final authHeaders = await account.authHeaders;
    final client = _GoogleAuthClient(authHeaders);
    return drive.DriveApi(client);
  }

  Future<void> backupToDrive() async {
    final driveApi = await _getDriveApi();
    await backupToJson();
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
    await prefs.setString('last_backup_time', DateTime.now().toIso8601String());
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
      final lastBackupStr = prefs.getString('last_backup_time');

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

  Future<void> restoreFromDrive() async {
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

    final file = await _backupFile;
    final sink = file.openWrite();
    await media.stream.pipe(sink);
    await sink.flush();
    await sink.close();

    await restoreFromJson(clearBeforeRestore: true);
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
