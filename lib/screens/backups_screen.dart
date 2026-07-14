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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace all data?'),
        content: const Text(
            'Restoring will delete everything currently in the app and '
            'replace it with the backup. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replace', style: TextStyle(color: Colors.red)),
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
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
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
        messenger.showSnackBar(const SnackBar(content: Text('Exported')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  String _mimeFor(String path) =>
      path.endsWith('.json') ? 'application/json' : 'text/csv';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Export')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LastBackupBanner(time: _lastBackup),
            const SizedBox(height: 12),
            const Text(
              'Backup & Restore',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                              content: const Text(
                                  'A newer backup exists on Google Drive. Overwriting it may cause data loss from other devices.\n\nDo you want to continue and overwrite the remote backup?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Overwrite',
                                      style: TextStyle(color: Colors.red)),
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
            const Text(
              'Google Drive requires a one-time sign-in setup in the build. '
              'If it fails, your data is still safe in local backups below.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Divider(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.save_alt),
              label: const Text('Backup locally (JSON)'),
              onPressed: _isWorking
                  ? null
                  : () => _runTask(
                      _backupService.backupToJson, 'Local JSON backup created'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.restore),
              label: const Text('Restore from local JSON'),
              onPressed: _isWorking
                  ? null
                  : () => _restore(() => _backupService.restoreFromJson(),
                      'Restored from local JSON'),
            ),
            const Divider(height: 32),
            const Text(
              'Download & Share',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Save your data to Files/Downloads, email it, or send it to '
              'another app.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
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
                  : () => _exportAndShare(exportInvestmentsToCsv,
                      'Finance Tracker — Investments'),
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
    final now = DateTime.now();
    final stale = time == null || now.difference(time!) > const Duration(days: 7);
    final color = stale ? Colors.orange : Colors.green;

    String label;
    if (time == null) {
      label = 'No backup yet — back up to avoid losing your data.';
    } else {
      final d = now.difference(time!);
      final ago = d.inDays >= 1
          ? '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago'
          : d.inHours >= 1
              ? '${d.inHours} hour${d.inHours == 1 ? '' : 's'} ago'
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
