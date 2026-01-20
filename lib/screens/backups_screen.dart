import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/expense_provider.dart';
import '../providers/investment_provider.dart';
import '../services/backup_service.dart';

class BackupsScreen extends StatefulWidget {
  const BackupsScreen({super.key});

  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

class _BackupsScreenState extends State<BackupsScreen> {
  final _backupService = BackupService();
  bool _isWorking = false;

  Future<void> _runTask(Future<void> Function() task, String success) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final expenseProvider = context.read<ExpenseProvider>();
    final investmentProvider = context.read<InvestmentProvider>();
    setState(() => _isWorking = true);
    try {
      await task();
      messenger.showSnackBar(SnackBar(content: Text(success)));
      // Refresh data after restore/backup operations
      await expenseProvider.reloadLoadedYears();
      await investmentProvider.fetchInvestments();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backups')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                  : () => _runTask(
                      _backupService.restoreFromDrive, 'Restored from Drive'),
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
                  : () => _runTask(() => _backupService.restoreFromJson(),
                      'Restored from local JSON'),
            ),
            const Divider(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.file_download),
              label: const Text('Export expenses CSV'),
              onPressed: _isWorking
                  ? null
                  : () => _runTask(exportExpensesToCsv,
                      'Expenses CSV exported to app storage'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.file_download),
              label: const Text('Export investments CSV'),
              onPressed: _isWorking
                  ? null
                  : () => _runTask(exportInvestmentsToCsv,
                      'Investments CSV exported to app storage'),
            ),
            const SizedBox(height: 12),
            if (_isWorking) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
