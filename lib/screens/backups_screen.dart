import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../providers/account_provider.dart';
import '../providers/budget_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/investment_provider.dart';
import '../providers/recurring_provider.dart';
import '../providers/template_provider.dart';
import '../services/backup_service.dart';
import 'import_screen.dart';
import '../utils/insets.dart';

class BackupsScreen extends StatefulWidget {
  const BackupsScreen({super.key});

  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

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

  /// Restore replaces all current data, so make the user confirm.
  Future<bool> _confirmRestore() async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.replaceAllTitle),
        content: Text(l.replaceAllBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.replace, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _restore(Future<void> Function() task, String success) async {
    if (await _confirmRestore()) {
      await _runTask(task, success);
      await _loadLastBackup();
    }
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
    } catch (e) {
      messenger.showSnackBar(_errorSnackBar(e));
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  /// Drive/backup failures carry a user-facing message (e.g. Drive not set up);
  /// show it plainly and give the reader time to act. Everything else falls
  /// back to a generic "Error: …".
  SnackBar _errorSnackBar(Object e) {
    if (e is DriveBackupException) {
      return SnackBar(
        content: Text(e.message),
        duration: const Duration(seconds: 8),
      );
    }
    return SnackBar(
        content: Text(AppLocalizations.of(context).errorWithDetails('$e')));
  }

  /// Generates a file and opens the system share sheet so the user can
  /// save it to Files/Downloads, email it, or send it elsewhere.
  Future<void> _exportAndShare(
      Future<File> Function() build, String subject) async {
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isWorking = true);
    try {
      final file = await build();
      final result = await Share.shareXFiles(
        [XFile(file.path, mimeType: _mimeFor(file.path))],
        subject: subject,
      );
      if (mounted && result.status == ShareResultStatus.success) {
        messenger.showSnackBar(SnackBar(content: Text(l.exported)));
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
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
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
                decoration: InputDecoration(labelText: l.passphrase),
                validator: (v) =>
                    (v == null || v.length < 4) ? l.passphraseMin : null,
              ),
              if (confirm)
                TextFormField(
                  controller: confirmController,
                  obscureText: true,
                  decoration:
                      InputDecoration(labelText: l.confirmPassphrase),
                  validator: (v) =>
                      v != controller.text ? l.passphraseMismatch : null,
                ),
              if (confirm)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l.passphraseForgotWarning,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
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
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.backupExport)),
      body: SingleChildScrollView(
        padding: scrollPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LastBackupBanner(time: _lastBackup),
            const SizedBox(height: 12),
            Text(
              l.backupRestore,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.cloud_upload),
              label: Text(l.backupToDriveBtn),
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
                              title: Text(l.newerBackupTitle),
                              content: Text(l.newerBackupBody),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(l.cancel),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text(l.overwrite,
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
                            _backupService.backupToDrive, l.backedUpToDrive);
                      } finally {
                        if (mounted) setState(() => _isWorking = false);
                      }
                    },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.cloud_download),
              label: Text(l.restoreFromDriveBtn),
              onPressed: _isWorking
                  ? null
                  : () => _restore(
                      _backupService.restoreFromDrive, l.restoredFromDrive),
            ),
            const SizedBox(height: 4),
            Text(
              l.driveSetupNote,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Divider(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.save_alt),
              label: Text(l.backupLocalJson),
              onPressed: _isWorking
                  ? null
                  : () => _runTask(
                      _backupService.backupToJson, l.localJsonCreated),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.restore),
              label: Text(l.restoreLocalJson),
              onPressed: _isWorking
                  ? null
                  : () => _restore(() => _backupService.restoreFromJson(),
                      l.restoredLocalJson),
            ),
            const Divider(height: 32),
            Text(
              l.encryptedBackup,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              l.encryptedBackupNote,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.lock),
              label: Text(l.encryptedBackupJson),
              onPressed: _isWorking
                  ? null
                  : () async {
                      final pass = await _promptPassphrase(
                          title: l.encryptBackupTitle,
                          action: l.encrypt,
                          confirm: true);
                      if (pass == null) return;
                      await _runTask(
                          () => _backupService.writeEncryptedBackup(pass),
                          l.encryptedBackupCreated);
                    },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.lock_open),
              label: Text(l.restoreEncryptedBackup),
              onPressed: _isWorking
                  ? null
                  : () async {
                      if (!await _confirmRestore()) return;
                      final pass = await _promptPassphrase(
                          title: l.restoreEncryptedBackup,
                          action: l.restoreAction);
                      if (pass == null) return;
                      await _runTask(
                          () => _backupService.restoreFromEncryptedFile(pass),
                          l.restoredEncrypted);
                    },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.ios_share),
              label: Text(l.downloadEncryptedBackup),
              onPressed: _isWorking
                  ? null
                  : () async {
                      final pass = await _promptPassphrase(
                          title: l.encryptBackupTitle,
                          action: l.encrypt,
                          confirm: true);
                      if (pass == null) return;
                      await _exportAndShare(
                          () => _backupService.writeEncryptedBackup(pass),
                          l.subjectEncrypted);
                    },
            ),
            const Divider(height: 32),
            Text(
              l.downloadShare,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              l.downloadShareNote,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: Text(l.downloadExpensesCsv),
              onPressed: _isWorking
                  ? null
                  : () => _exportAndShare(
                      exportExpensesToCsv, l.subjectExpenses),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: Text(l.downloadInvestmentsCsv),
              onPressed: _isWorking
                  ? null
                  : () => _exportAndShare(
                      exportInvestmentsToCsv, l.subjectInvestments),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: Text(l.downloadFullJson),
              onPressed: _isWorking
                  ? null
                  : () => _exportAndShare(_backupService.writeJsonBackupFile,
                      l.subjectFullBackup),
            ),
            const Divider(height: 32),
            OutlinedButton.icon(
              icon: const Icon(Icons.upload_file),
              label: Text(l.importFromCsv),
              onPressed: _isWorking
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ImportScreen()),
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
    final l = AppLocalizations.of(context);
    final now = DateTime.now();
    final stale = time == null || now.difference(time!) > const Duration(days: 7);
    final color = stale ? Colors.orange : Colors.green;

    String label;
    if (time == null) {
      label = l.noBackupYet;
    } else {
      final d = now.difference(time!);
      final ago = d.inDays >= 1
          ? l.daysAgo(d.inDays)
          : d.inHours >= 1
              ? l.hoursAgo(d.inHours)
              : l.justNow;
      label = l.lastBackup(ago);
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
