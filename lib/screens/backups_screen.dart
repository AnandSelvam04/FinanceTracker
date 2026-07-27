import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/account_provider.dart';
import '../providers/budget_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/investment_provider.dart';
import '../providers/recurring_provider.dart';
import '../providers/template_provider.dart';
import '../services/backup_service.dart';
import 'import_screen.dart';
import '../utils/insets.dart';

/// A restore, parameterised by whether the user has already agreed to apply a
/// backup that contains no rows.
typedef _RestoreTask = Future<void> Function({bool allowEmpty});

/// Unwinds a task the user backed out of part-way through, so [_runTask]
/// reports neither success nor an error.
class _Cancelled implements Exception {
  const _Cancelled();
}

class BackupsScreen extends StatefulWidget {
  const BackupsScreen({super.key});

  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

/// Minimum length when *setting* a backup passphrase. Encrypted backups are
/// shared off-device, so the passphrase is their only protection.
const _minPassphraseLength = 12;

class _BackupsScreenState extends State<BackupsScreen> {
  final _backupService = BackupService();
  bool _isWorking = false;
  DateTime? _lastBackup;

  @override
  void initState() {
    super.initState();
    _loadLastBackup();
  }

  Future<void> _loadLastBackup() async {
    final t = await _backupService.lastBackupTime();
    if (mounted) setState(() => _lastBackup = t);
  }

  /// A restore that turned out to contain nothing, which the user then
  /// declined to apply. Unwinds the task without reporting success or an error.
  static const _cancelled = _Cancelled();

  /// Second confirmation, shown only when the backup parsed cleanly but has no
  /// rows at all. The generic "Replace all data?" prompt isn't enough here —
  /// the user thinks they are restoring something.
  Future<bool> _confirmEmptyRestore(String detail) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('This backup is empty'),
        content: Text('$detail\n\nContinue anyway?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Erase everything',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Restore replaces all current data, so make the user confirm.
  Future<bool> _confirmRestore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace all data?'),
        content: const Text(
            'Restoring will delete everything currently in the app and replace it with the backup. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Replace', style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Runs a restore behind the "Replace all data?" confirmation. If the backup
  /// turns out to be empty the service refuses it, and we ask a second time
  /// before retrying with [allowEmpty] — otherwise a `{}` file would silently
  /// erase everything.
  Future<void> _restore(_RestoreTask task, String success) async {
    if (!await _confirmRestore()) return;
    await _runTask(() async {
      try {
        await task();
      } on EmptyBackupException catch (e) {
        if (!mounted || !await _confirmEmptyRestore(e.message)) {
          throw _cancelled;
        }
        await task(allowEmpty: true);
      }
    }, success);
    await _loadLastBackup();
  }

  Future<void> _runTask(Future<void> Function() task, String success) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final expenseProvider = context.read<ExpenseProvider>();
    final investmentProvider = context.read<InvestmentProvider>();
    final budgetProvider = context.read<BudgetProvider>();
    final accountProvider = context.read<AccountProvider>();
    final recurringProvider = context.read<RecurringProvider>();
    final templateProvider = context.read<TemplateProvider>();
    setState(() => _isWorking = true);
    try {
      await task();
      messenger.showSnackBar(SnackBar(content: Text(success)));
      // Refresh data after restore/backup operations
      await expenseProvider.reloadLoadedYears();
      await investmentProvider.fetchInvestments();
      await budgetProvider.fetchBudgets();
      await accountProvider.fetchAccounts();
      await recurringProvider.fetchRules();
      await templateProvider.fetchTemplates();
      await _loadLastBackup();
    } on _Cancelled {
      // The user backed out of a second confirmation; nothing to report.
    } catch (e) {
      messenger.showSnackBar(_errorSnackBar(e));
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  /// Drive/backup failures carry a user-facing message (e.g. Drive not set up,
  /// or a file that isn't a backup); show it plainly and give the reader time
  /// to act. Everything else falls back to a generic "Error: …".
  SnackBar _errorSnackBar(Object e) {
    if (e is DriveBackupException) {
      return SnackBar(
        content: Text(e.message),
        duration: const Duration(seconds: 8),
      );
    }
    if (e is BackupFormatException || e is EmptyBackupException) {
      return SnackBar(
        content: Text('$e'),
        duration: const Duration(seconds: 8),
      );
    }
    return SnackBar(content: Text('Error: $e'));
  }

  /// Generates a file and opens the system share sheet so the user can
  /// save it to Files/Downloads, email it, or send it elsewhere.
  Future<void> _exportAndShare(
      Future<File> Function() build, String subject) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isWorking = true);
    try {
      final file = await build();
      final result = await Share.shareXFiles(
        [XFile(file.path, mimeType: _mimeFor(file.path))],
        subject: subject,
      );
      if (mounted && result.status == ShareResultStatus.success) {
        messenger.showSnackBar(SnackBar(content: const Text('Exported')));
      }
    } catch (e) {
      messenger.showSnackBar(_errorSnackBar(e));
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  String _mimeFor(String path) =>
      path.endsWith('.json') ? 'application/json' : 'text/csv';

  /// Prompts for a passphrase. When [confirm] is set, requires it to be typed
  /// twice and warns that a lost passphrase is unrecoverable. Returns null if
  /// the user cancels.
  Future<String?> _promptPassphrase(
      {required String title,
      required String action,
      bool confirm = false}) async {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: controller,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Passphrase',
                    helperText: 'At least 12 characters',
                  ),
                  // These files are meant to leave the device via the share
                  // sheet, so the passphrase is the only thing protecting them.
                  // Four characters fall to a brute-force in seconds; only
                  // enforced when setting a passphrase, so existing backups
                  // stay restorable.
                  validator: confirm
                      ? (v) => (v == null || v.length < _minPassphraseLength)
                          ? 'Use at least $_minPassphraseLength characters'
                          : null
                      : (v) => (v == null || v.isEmpty)
                          ? 'Enter the passphrase'
                          : null,
                ),
                if (confirm)
                  TextFormField(
                    controller: confirmController,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Confirm passphrase'),
                    validator: (v) => v != controller.text
                        ? 'Passphrases do not match'
                        : null,
                  ),
                if (confirm)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'If you forget this passphrase, the backup cannot be recovered.',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(ctx, controller.text);
                }
              },
              child: Text(action),
            ),
          ],
        ),
      );
    } finally {
      // Dispose once the dialog closes. These held a backup passphrase, so
      // leaking them left it sitting in the heap for the rest of the session.
      controller.dispose();
      confirmController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Export')),
      body: SingleChildScrollView(
        padding: scrollPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LastBackupBanner(time: _lastBackup),
            const SizedBox(height: 12),
            Text(
              'Backup & Restore',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Backup to Google Drive'),
              onPressed: _isWorking
                  ? null
                  : () async {
                      setState(() => _isWorking = true);
                      try {
                        final isNewer =
                            await _backupService.isRemoteBackupNewer();
                        if (!context.mounted) return;

                        if (isNewer) {
                          // ignore: use_build_context_synchronously
                          final shouldOverwrite = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Warning: Newer Backup Found'),
                              content: Text(
                                  'A newer backup exists on Google Drive. Overwriting it may cause data loss from other devices.\n\nDo you want to continue and overwrite the remote backup?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text('Overwrite',
                                      style:
                                          const TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );

                          if (shouldOverwrite != true) {
                            setState(() => _isWorking = false);
                            return;
                          }
                        }
                        await _runTask(
                            _backupService.backupToDrive, 'Backed up to Drive');
                      } finally {
                        if (mounted) setState(() => _isWorking = false);
                      }
                    },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.cloud_download),
              label: const Text('Restore from Google Drive'),
              onPressed: _isWorking
                  ? null
                  : () => _restore(
                      _backupService.restoreFromDrive, 'Restored from Drive'),
            ),
            const SizedBox(height: 4),
            Text(
              'Google Drive requires a one-time sign-in setup in the build. If it fails, your data is still safe in local backups below.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Divider(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.save_alt),
              label: const Text('Backup locally (JSON)'),
              onPressed: _isWorking
                  ? null
                  // writeJsonBackupFile, not backupToJson: it applies the
                  // device key when at-rest encryption is on, so this button
                  // can't leave a readable copy of everything on disk.
                  : () => _runTask(_backupService.writeJsonBackupFile,
                      'Local JSON backup created'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.restore),
              label: const Text('Restore from local JSON'),
              onPressed: _isWorking
                  ? null
                  : () => _restore(
                      ({bool allowEmpty = false}) => _backupService
                          .restoreFromJson(allowEmpty: allowEmpty),
                      'Restored from local JSON'),
            ),
            const Divider(height: 32),
            Text(
              'Encrypted backup',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Protect an exported backup with a passphrase (AES-256). Keep the passphrase safe — it is required to restore and cannot be reset.',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.lock),
              label: const Text('Encrypted backup (JSON)'),
              onPressed: _isWorking
                  ? null
                  : () async {
                      final pass = await _promptPassphrase(
                          title: 'Encrypt backup',
                          action: 'Encrypt',
                          confirm: true);
                      if (pass == null) return;
                      await _runTask(
                          () => _backupService.writeEncryptedBackup(pass),
                          'Encrypted backup created');
                    },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.lock_open),
              label: const Text('Restore encrypted backup'),
              onPressed: _isWorking
                  ? null
                  : () async {
                      if (!await _confirmRestore()) return;
                      final pass = await _promptPassphrase(
                          title: 'Restore encrypted backup', action: 'Restore');
                      if (pass == null) return;
                      await _runTask(() async {
                        try {
                          await _backupService.restoreFromEncryptedFile(pass);
                        } on EmptyBackupException catch (e) {
                          if (!mounted ||
                              !await _confirmEmptyRestore(e.message)) {
                            throw _cancelled;
                          }
                          await _backupService.restoreFromEncryptedFile(pass,
                              allowEmpty: true);
                        }
                      }, 'Restored from encrypted backup');
                    },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.ios_share),
              label: const Text('Download encrypted backup'),
              onPressed: _isWorking
                  ? null
                  : () async {
                      final pass = await _promptPassphrase(
                          title: 'Encrypt backup',
                          action: 'Encrypt',
                          confirm: true);
                      if (pass == null) return;
                      await _exportAndShare(
                          () => _backupService.writeEncryptedBackup(pass),
                          'Finance Tracker — Encrypted Backup');
                    },
            ),
            const Divider(height: 32),
            Text(
              'Download & Share',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Save your data to Files/Downloads, email it, or send it to another app.',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Download expenses (CSV)'),
              onPressed: _isWorking
                  ? null
                  : () => _exportAndShare(
                      exportExpensesToCsv, 'Finance Tracker — Expenses'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Download investments (CSV)'),
              onPressed: _isWorking
                  ? null
                  : () => _exportAndShare(
                      exportInvestmentsToCsv, 'Finance Tracker — Investments'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Download full data (JSON)'),
              onPressed: _isWorking
                  ? null
                  : () => _exportAndShare(_backupService.writeJsonBackupFile,
                      'Finance Tracker — Full Backup'),
            ),
            const Divider(height: 32),
            OutlinedButton.icon(
              icon: const Icon(Icons.upload_file),
              label: const Text('Import from CSV'),
              onPressed: _isWorking
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ImportScreen()),
                      ),
            ),
            const SizedBox(height: 12),
            if (_isWorking) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

/// Shows when the app was last backed up, warning if it's stale (>7 days)
/// or has never happened — a safety nudge for on-device-only data.
class _LastBackupBanner extends StatelessWidget {
  final DateTime? time;
  const _LastBackupBanner({required this.time});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final stale =
        time == null || now.difference(time!) > const Duration(days: 7);
    final color = stale ? Colors.orange : Colors.green;

    String label;
    if (time == null) {
      label = 'No backup yet — back up to avoid losing your data.';
    } else {
      final d = now.difference(time!);
      final ago = d.inDays >= 1
          ? (d.inDays == 1 ? '1 day ago' : '${d.inDays} days ago')
          : d.inHours >= 1
              ? (d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago')
              : 'just now';
      label = 'Last backup: $ago';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(stale ? Icons.warning_amber : Icons.check_circle,
              color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
