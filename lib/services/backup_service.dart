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
        'ToAccountId'
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
  Future<bool> autoBackupIfDue(
      {Duration minInterval = const Duration(days: 1)}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastAutoBackup);
    final last = raw == null ? null : DateTime.tryParse(raw);
    if (last != null && DateTime.now().difference(last) < minInterval) {
      return false;
    }
    await backupToJson();
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
      'version': 4,
      'expenses': expenses.map((e) => e.toMap()).toList(),
      'investments': investments.map((i) => i.toMap()).toList(),
      'budgets': budgets.map((b) => b.toMap()).toList(),
      'accounts': accounts.map((a) => a.toMap()).toList(),
      'recurring_rules': recurringRules.map((r) => r.toMap()).toList(),
      'templates': templates.map((t) => t.toMap()).toList(),
    };
  }

  Future<void> backupToJson() async {
    final data = await _collectBackupData();
    final file = await _backupFile;
    await file.writeAsString(jsonEncode(data));
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

  Future<void> restoreFromJson({bool clearBeforeRestore = true}) async {
    final file = await _backupFile;
    if (!await file.exists()) return;
    final content = await file.readAsString();
    await _applyRestore(jsonDecode(content),
        clearBeforeRestore: clearBeforeRestore);
  }

  Future<void> _applyRestore(dynamic data,
      {bool clearBeforeRestore = true}) async {
    final db = DBService();
    if (clearBeforeRestore) {
      await db.clearAll();
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

    // Restore accounts before expenses so account links resolve
    // (ids are preserved because toMap includes them). Older backups
    // have no 'accounts' key; skip gracefully.
    for (var a in data['accounts'] ?? []) {
      await db.insertAccount(
          Account.fromMap(fix(a, [DbConstants.colOpeningBalance])));
    }
    for (var e in data['expenses'] ?? []) {
      await db.insertExpense(Expense.fromMap(fix(e, [DbConstants.colAmount])));
    }
    for (var i in data['investments'] ?? []) {
      await db.insertInvestment(
          Investment.fromMap(fix(i, [DbConstants.colAmount])));
    }
    // Older backups have no 'budgets' key; skip gracefully.
    for (var b in data['budgets'] ?? []) {
      await db.insertBudget(Budget.fromMap(fix(b, [DbConstants.colAmount])));
    }
    for (var r in data['recurring_rules'] ?? []) {
      await db.insertRecurringRule(
          RecurringRule.fromMap(fix(r, [DbConstants.colAmount])));
    }
    for (var t in data['templates'] ?? []) {
      await db
          .insertTemplate(TxTemplate.fromMap(fix(t, [DbConstants.colAmount])));
    }
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

    final driveFile = drive.File()
      ..name = 'finance_backup.json'
      ..parents = ['appDataFolder'];

    await driveApi.files.create(
      driveFile,
      uploadMedia: drive.Media(file.openRead(), length),
    );

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
