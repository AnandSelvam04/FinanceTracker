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
import 'db_service.dart';

// Export expenses to CSV

Future<File> exportExpensesToCsv() async {
  final expenses = await DBService().getExpenses();
  final List<List<dynamic>> rows = [
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
          e.amount,
          e.date.toIso8601String(),
          e.category,
          e.paymentMode,
          e.type,
          e.accountId ?? '',
          e.toAccountId ?? '',
        ]),
  ];
  String csvData = const ListToCsvConverter().convert(rows);
  final backupService = BackupService();
  final path = await backupService._localPath;
  final file = File('$path/expenses_export.csv');
  await file.writeAsString(csvData);
  return file;
}

// Export investments to CSV

Future<File> exportInvestmentsToCsv() async {
  final investments = await DBService().getInvestments();
  final List<List<dynamic>> rows = [
    ['ID', 'Name', 'Amount', 'Date', 'Type'],
    ...investments.map((i) => [
          i.id ?? '',
          i.name,
          i.amount,
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

  Future<File> get _backupFile async {
    final path = await _localPath;
    return File('$path/finance_backup.json');
  }

  /// Writes the full-data JSON backup and returns the file so it can be
  /// shared/downloaded by the user.
  Future<File> writeJsonBackupFile() async {
    await backupToJson();
    return _backupFile;
  }

  Future<void> backupToJson() async {
    final expenses = await DBService().getExpenses();
    final investments = await DBService().getInvestments();
    final budgets = await DBService().getBudgets();
    final accounts = await DBService().getAccounts();
    final recurringRules = await DBService().getRecurringRules();
    final templates = await DBService().getTemplates();
    final data = {
      'version': 3,
      'expenses': expenses.map((e) => e.toMap()).toList(),
      'investments': investments.map((i) => i.toMap()).toList(),
      'budgets': budgets.map((b) => b.toMap()).toList(),
      'accounts': accounts.map((a) => a.toMap()).toList(),
      'recurring_rules': recurringRules.map((r) => r.toMap()).toList(),
      'templates': templates.map((t) => t.toMap()).toList(),
    };
    final file = await _backupFile;
    await file.writeAsString(jsonEncode(data));
  }

  Future<void> restoreFromJson({bool clearBeforeRestore = true}) async {
    final file = await _backupFile;
    if (!await file.exists()) return;
    final content = await file.readAsString();
    final data = jsonDecode(content);
    final db = DBService();
    if (clearBeforeRestore) {
      await db.clearAll();
    }
    // Restore accounts before expenses so account links resolve
    // (ids are preserved because toMap includes them). Older backups
    // have no 'accounts' key; skip gracefully.
    for (var a in data['accounts'] ?? []) {
      await db.insertAccount(Account.fromMap(Map<String, dynamic>.from(a)));
    }
    for (var e in data['expenses'] ?? []) {
      await db.insertExpense(Expense.fromMap(Map<String, dynamic>.from(e)));
    }
    for (var i in data['investments'] ?? []) {
      await db
          .insertInvestment(Investment.fromMap(Map<String, dynamic>.from(i)));
    }
    // Older backups have no 'budgets' key; skip gracefully.
    for (var b in data['budgets'] ?? []) {
      await db.insertBudget(Budget.fromMap(Map<String, dynamic>.from(b)));
    }
    for (var r in data['recurring_rules'] ?? []) {
      await db.insertRecurringRule(
          RecurringRule.fromMap(Map<String, dynamic>.from(r)));
    }
    for (var t in data['templates'] ?? []) {
      await db.insertTemplate(TxTemplate.fromMap(Map<String, dynamic>.from(t)));
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
