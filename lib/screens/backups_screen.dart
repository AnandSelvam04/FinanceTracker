import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/account_provider.dart';
import '../providers/budget_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/investment_provider.dart';
import '../providers/recurring_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/template_provider.dart';
import '../services/backup_service.dart';
import '../services/db_service.dart';
import '../services/excel_export.dart';
import 'import_screen.dart';
import '../utils/app_colors.dart';
import '../utils/date_format.dart';
import '../utils/insets.dart';
import '../widgets/month_selector.dart';
import '../widgets/section_header.dart';
import '../widgets/dispose_with_route.dart';
import '../utils/font_sizes.dart';

part 'backups/dialogs.dart';

class BackupsScreen extends StatefulWidget {
  const BackupsScreen({super.key});

  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

class _BackupsScreenState extends State<BackupsScreen> {
  final _backupService = BackupService();
  bool _isWorking = false;

  /// The dates the CSV and Excel downloads cover; null is everything. The
  /// end is the day after the last one included.
  ({DateTime from, DateTime to, String label})? _exportPeriod;

  /// Lets the user narrow the CSV and Excel downloads: everything, a range
  /// of dates, one month or one year.
  Future<void> _pickExportPeriod() async {
    final now = DateTime.now();
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Download what?'),
        children: [
          for (final (key, label) in const [
            ('all', 'All'),
            ('dates', 'A date range…'),
            ('month', 'A month…'),
            ('year', 'A year…'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, key),
              child: Text(label),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'all':
        setState(() => _exportPeriod = null);
      case 'dates':
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: now,
        );
        if (picked == null || !mounted) return;
        setState(() => _exportPeriod = (
              from: DateTime(
                  picked.start.year, picked.start.month, picked.start.day),
              // The whole of the last day picked.
              to: DateTime(
                  picked.end.year, picked.end.month, picked.end.day + 1),
              label: '${formatShortDate(picked.start)} – '
                  '${formatShortDate(picked.end)}',
            ));
      case 'month':
        final picked = await _pickMonthOrYear(
            context, _exportPeriod?.from ?? now,
            yearOnly: false);
        if (picked == null || !mounted) return;
        setState(() => _exportPeriod = (
              from: DateTime(picked.$1, picked.$2),
              to: DateTime(picked.$1, picked.$2 + 1),
              label: formatMonthYear(picked.$1, picked.$2),
            ));
      case 'year':
        final picked = await _pickMonthOrYear(
            context, _exportPeriod?.from ?? now,
            yearOnly: true);
        if (picked == null || !mounted) return;
        setState(() => _exportPeriod = (
              from: DateTime(picked.$1),
              to: DateTime(picked.$1 + 1),
              label: '${picked.$1}',
            ));
    }
  }

  /// When a backup last left the phone (Drive, or shared out). The on-device
  /// auto-backup doesn't count: it is lost along with the phone.
  DateTime? _lastBackup;

  /// Whether at-rest database encryption is on. Backups that leave the phone
  /// then need a passphrase: the device key can't open them anywhere else.
  bool _dbEncrypted = false;

  /// Email of the Google account signed in for Drive, or null when nobody is.
  String? _driveEmail;

  /// Whether automatic Drive backup is on, what its last attempt did, and
  /// when this phone last wrote to Drive.
  bool _autoDrive = false;
  AutoDriveStatus? _autoDriveStatus;
  DateTime? _lastDriveBackup;

  @override
  void initState() {
    super.initState();
    _loadLastBackup();
    _loadDriveAccount();
    _loadEncryption();
    _loadAutoDrive();
  }

  Future<void> _loadAutoDrive() async {
    final on = await _backupService.isAutoDriveBackupOn();
    final status = await _backupService.lastAutoDriveStatus();
    final last = await _backupService.lastDriveBackupTime();
    if (!mounted) return;
    setState(() {
      _autoDrive = on;
      _autoDriveStatus = status;
      _lastDriveBackup = last;
    });
  }

  Future<String?> _promptAutoDrivePassphrase() => _promptPassphrase(
        context,
        title: 'Protect automatic backups',
        action: 'Save',
        message: 'Your database is encrypted, so the Drive copy is sealed '
            'with a passphrase. It is kept in this phone\'s secure storage '
            'for the automatic backups. You will need it to restore on a '
            'new phone.',
        confirm: true,
      );

  Future<void> _setAutoDrive(bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isWorking = true);
    try {
      if (!on) {
        await _backupService.disableAutoDriveBackup();
      } else {
        String? passphrase;
        if (_dbEncrypted) {
          passphrase = await _promptAutoDrivePassphrase();
          if (passphrase == null) return;
        }
        await _backupService.enableAutoDriveBackup(passphrase: passphrase);
        // Back up straight away, so the switch shows a real result.
        final status = await _backupService.autoDriveBackupIfDue(force: true);
        messenger.showSnackBar(SnackBar(
          content: Text(status == AutoDriveStatus.done
              ? 'Automatic Drive backup is on. Backed up just now.'
              : 'Automatic Drive backup is on. ${_autoDriveProblem(status)}'),
          duration: const Duration(seconds: 6),
        ));
        await _loadDriveAccount();
        await _loadLastBackup();
      }
    } catch (e) {
      messenger.showSnackBar(_errorSnackBar(e));
    } finally {
      await _loadAutoDrive();
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _setAutoDrivePassphrase() async {
    final passphrase = await _promptAutoDrivePassphrase();
    if (passphrase == null) return;
    await _runTask(() async {
      await _backupService.setAutoDrivePassphrase(passphrase);
      final status = await _backupService.autoDriveBackupIfDue(force: true);
      if (status != AutoDriveStatus.done) {
        throw DriveBackupException(_autoDriveProblem(status));
      }
    }, 'Passphrase saved. Backed up to Drive.');
    await _loadAutoDrive();
  }

  /// What a status that didn't upload means for the user, and what to do.
  static String _autoDriveProblem(AutoDriveStatus? status) {
    switch (status) {
      case AutoDriveStatus.notSignedIn:
        return 'Not signed in to Google. Back up to Drive once by hand to '
            'sign in.';
      case AutoDriveStatus.needsPassphrase:
        return 'Your database is encrypted, so automatic backups need a '
            'passphrase. Tap Set passphrase.';
      case AutoDriveStatus.remoteNewer:
        return 'The Drive copy was saved by another phone, so it was not '
            'overwritten. Back up by hand once to choose which to keep.';
      case AutoDriveStatus.failed:
        return 'The last try failed (offline?). It tries again later.';
      default:
        return 'The first backup runs the next time the app opens.';
    }
  }

  /// One line under the switch: when it last backed up, or what's wrong.
  String _autoDriveSubtitle() {
    if (!_autoDrive) {
      return 'Once a day when the app opens, to the signed-in account. '
          'Never overwrites a newer copy from another phone.';
    }
    final status = _autoDriveStatus;
    if (status == null || status == AutoDriveStatus.done) {
      final last = _lastDriveBackup;
      return last == null
          ? 'On. The first backup runs the next time the app opens.'
          : 'On. Last backed up on ${formatCompactDate(last)}.';
    }
    return _autoDriveProblem(status);
  }

  Future<void> _loadLastBackup() async {
    final t = await _backupService.lastOffDeviceBackupTime();
    if (mounted) setState(() => _lastBackup = t);
  }

  Future<void> _loadEncryption() async {
    try {
      final on = await DBService().isEncryptionEnabled();
      if (mounted) setState(() => _dbEncrypted = on);
    } catch (_) {
      // Unknown: leave it off; backupToDrive still refuses a plain upload.
    }
  }

  Future<void> _loadDriveAccount() async {
    final email = await _backupService.currentDriveAccountEmail();
    if (mounted) setState(() => _driveEmail = email);
  }

  Future<void> _switchDriveAccount() async {
    await _backupService.signOutDrive();
    if (mounted) setState(() => _driveEmail = null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Signed out of Google Drive. The next backup will ask which '
                'account to use.')),
      );
    }
  }

  /// A restore that turned out to contain nothing, which the user then
  /// declined to apply. Unwinds the task without reporting success or an error.
  static const _cancelled = _Cancelled();

  /// Runs a restore behind the "Replace all data?" confirmation. If the backup
  /// turns out to be empty the service refuses it, and we ask a second time
  /// before retrying with [allowEmpty] — otherwise a `{}` file would silently
  /// erase everything.
  Future<void> _restore(_RestoreTask task, String success) async {
    if (!await _confirmRestore(context)) return;
    await _runTask(() async {
      try {
        await task();
      } on EmptyBackupException catch (e) {
        if (!mounted || !await _confirmEmptyRestore(context, e.message)) {
          throw _cancelled;
        }
        await task(allowEmpty: true);
      }
    }, success);
    await _loadLastBackup();
  }

  /// Like [_restore], for backups that may be sealed with a passphrase: asks
  /// for it when the backup needs one (again, if it was wrong) and retries.
  Future<void> _restoreProtected(
      _ProtectedRestoreTask task, String success) async {
    if (!await _confirmRestore(context)) return;
    String? passphrase;
    var allowEmpty = false;
    await _runTask(() async {
      while (true) {
        try {
          await task(allowEmpty: allowEmpty, passphrase: passphrase);
          return;
        } on EmptyBackupException catch (e) {
          if (!mounted || !await _confirmEmptyRestore(context, e.message)) {
            throw _cancelled;
          }
          allowEmpty = true;
        } on PassphraseRequiredException catch (e) {
          if (!mounted) throw _cancelled;
          passphrase = await _promptPassphrase(context,
              title: e.wrongPassphrase
                  ? 'Wrong passphrase — try again'
                  : 'Backup passphrase',
              action: 'Restore');
          if (passphrase == null) throw _cancelled;
        }
      }
    }, success);
    await _loadLastBackup();
  }

  /// Restores a backup file the user picks: a download, an emailed backup, or
  /// a copy from another phone.
  Future<void> _restoreFromPickedFile() async {
    final result = await FilePicker.platform.pickFiles();
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    await _restoreProtected(
        ({bool allowEmpty = false, String? passphrase}) =>
            _backupService.restoreFromFile(path,
                passphrase: passphrase, allowEmpty: allowEmpty),
        'Restored from file');
  }

  /// Restores one of the dated copies the daily backup keeps, for undoing a
  /// mistake that the latest backup has already taken in.
  Future<void> _restoreFromHistory() async {
    final history = await _backupService.backupHistory();
    if (!mounted) return;
    if (history.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No earlier backups yet — one is kept each day.')));
      return;
    }
    final picked = await showDialog<File>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Restore an earlier backup'),
        children: [
          for (final h in history)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, h.file),
              child: Text(formatDateWithDay(h.day)),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    await _restoreProtected(
        ({bool allowEmpty = false, String? passphrase}) =>
            _backupService.restoreFromFile(picked.path,
                passphrase: passphrase, allowEmpty: allowEmpty),
        'Restored the earlier backup');
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
    final goalProvider = context.read<GoalProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    setState(() => _isWorking = true);
    try {
      _backupService.missingReceiptPhotos = 0;
      await task();
      // Only a restore sets this: its transactions whose receipt photo isn't
      // on this phone (backups don't carry the images).
      final lost = _backupService.missingReceiptPhotos;
      messenger.showSnackBar(SnackBar(
          content: Text(lost == 0
              ? success
              : '$success. ${lost == 1 ? '1 receipt photo was' : '$lost receipt photos were'} '
                  'not in the backup.')));
      // Refresh data after restore/backup operations
      await expenseProvider.reloadLoadedYears();
      await investmentProvider.fetchInvestments();
      await budgetProvider.fetchBudgets();
      await accountProvider.fetchAccounts();
      await recurringProvider.fetchRules();
      await templateProvider.fetchTemplates();
      await goalProvider.fetchGoals();
      // A full restore brings back the backup's settings too.
      await settingsProvider.load();
      await _loadLastBackup();
    } on _Cancelled {
      // The user backed out of a second confirmation; nothing to report.
    } catch (e) {
      messenger.showSnackBar(_errorSnackBar(e));
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  /// Generates a file and opens the system share sheet so the user can
  /// save it to Files/Downloads, email it, or send it elsewhere.
  ///
  /// Set [offDevice] for a full backup that can be restored elsewhere: once
  /// shared it counts as a copy that survives losing the phone.
  Future<void> _exportAndShare(Future<File> Function() build, String subject,
      {bool offDevice = false}) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isWorking = true);
    try {
      final file = await build();
      final result = await Share.shareXFiles(
        [XFile(file.path, mimeType: _mimeFor(file.path))],
        subject: subject,
      );
      if (result.status == ShareResultStatus.success) {
        if (offDevice) {
          await _backupService.markSharedOffDevice();
          await _loadLastBackup();
        }
        if (mounted) {
          messenger.showSnackBar(SnackBar(content: const Text('Exported')));
        }
      }
    } catch (e) {
      messenger.showSnackBar(_errorSnackBar(e));
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  /// Verifies the local backup is restorable and shows the row counts (or the
  /// reason it isn't), without touching the live database.
  Future<void> _verifyBackup() async {
    setState(() => _isWorking = true);
    final result = await _backupService.verifyLocalBackup();
    if (!mounted) return;
    setState(() => _isWorking = false);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(result.ok ? 'Backup looks good' : 'Backup problem'),
        content: result.ok
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your local backup opened and every row is intact — '
                      '${result.total} row${result.total == 1 ? '' : 's'} '
                      'total:'),
                  const SizedBox(height: 8),
                  for (final e in result.counts.entries)
                    if (e.value > 0)
                      Text('• ${_prettyTable(e.key)}: ${e.value}'),
                ],
              )
            : Text(result.error ?? 'Could not verify the backup.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
            // Three questions, three groups: where is my backup, how do I get
            // it back, and how do I take data out. The screen used to list
            // fifteen actions under headings that mixed all three.
            const SectionHeader('Back up'),
            const SizedBox(height: 4),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.cloud_upload),
                    title: const Text('Back up to Google Drive'),
                    subtitle: const Text(
                        'Stored privately in the app-data folder; only this '
                        'app can read it'),
                    enabled: !_isWorking,
                    onTap: () async {
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
                                      style: TextStyle(
                                          color:
                                              Theme.of(ctx).colorScheme.error)),
                                ),
                              ],
                            ),
                          );

                          if (shouldOverwrite != true) {
                            setState(() => _isWorking = false);
                            return;
                          }
                        }
                        String? passphrase;
                        if (_dbEncrypted) {
                          if (!context.mounted) return;
                          passphrase = await _promptPassphrase(
                            context,
                            title: 'Protect the Drive backup',
                            action: 'Back up',
                            message: 'Your database is encrypted, so the Drive '
                                'copy is sealed with a passphrase. You will '
                                'need it to restore on a new phone.',
                            confirm: true,
                          );
                          if (passphrase == null) return;
                        }
                        await _runTask(
                            () => _backupService.backupToDrive(
                                passphrase: passphrase),
                            'Backed up to Drive');
                        // Signing in during the backup may have established the
                        // account — show it.
                        await _loadDriveAccount();
                        await _loadAutoDrive();
                      } finally {
                        if (mounted) setState(() => _isWorking = false);
                      }
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.cloud_sync),
                    title: const Text('Back up to Drive automatically'),
                    subtitle: Text(_autoDriveSubtitle()),
                    value: _autoDrive,
                    onChanged: _isWorking ? null : _setAutoDrive,
                  ),
                  if (_autoDrive &&
                      _autoDriveStatus == AutoDriveStatus.needsPassphrase)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TextButton(
                          onPressed:
                              _isWorking ? null : _setAutoDrivePassphrase,
                          child: const Text('Set passphrase'),
                        ),
                      ),
                    ),
                  // Which Google account holds the backup, and where it lives.
                  if (_driveEmail != null)
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.account_circle,
                          color: mutedTextColor(context)),
                      title: Text('Backs up to $_driveEmail',
                          style: TextStyle(
                              fontSize: FontSizes.body,
                              color: mutedTextColor(context))),
                      trailing: TextButton(
                        onPressed: _isWorking ? null : _switchDriveAccount,
                        child: const Text('Switch'),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        'Not signed in to Google Drive yet — the first backup '
                        'will ask which account to use.',
                        style: TextStyle(
                            fontSize: FontSizes.caption,
                            color: mutedTextColor(context)),
                      ),
                    ),
                ],
              ),
            ),
            const SectionHeader('Restore',
                padding: EdgeInsets.fromLTRB(0, 20, 0, 4)),
            Text(
              'Restoring replaces everything in the app with the backup.',
              style: TextStyle(
                  fontSize: FontSizes.body, color: mutedTextColor(context)),
            ),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.cloud_download),
                    title: const Text('Restore from Google Drive'),
                    enabled: !_isWorking,
                    onTap: () async {
                      await _restoreProtected(_backupService.restoreFromDrive,
                          'Restored from Drive');
                      await _loadDriveAccount();
                      await _loadAutoDrive();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_open),
                    title: const Text('Restore from a file'),
                    subtitle: const Text(
                        'A downloaded, emailed, or other phone\'s backup'),
                    enabled: !_isWorking,
                    onTap: _restoreFromPickedFile,
                  ),
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('Restore an earlier backup'),
                    subtitle: Text('One copy kept per day for the last '
                        '${BackupService.historyDays} days'),
                    enabled: !_isWorking,
                    onTap: _restoreFromHistory,
                  ),
                ],
              ),
            ),
            const SectionHeader('Export & import',
                padding: EdgeInsets.fromLTRB(0, 20, 0, 4)),
            Text(
              'Save your data to Files/Downloads, email it, or send it to another app.',
              style: TextStyle(
                  fontSize: FontSizes.body, color: mutedTextColor(context)),
            ),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.date_range),
                    title: Text('Dates: ${_exportPeriod?.label ?? 'All'}'),
                    subtitle: const Text(
                        'Applies to the CSV and Excel downloads below'),
                    trailing: const Icon(Icons.arrow_drop_down),
                    enabled: !_isWorking,
                    onTap: _pickExportPeriod,
                  ),
                  ListTile(
                    leading: const Icon(Icons.download),
                    title: const Text('Download expenses (CSV)'),
                    enabled: !_isWorking,
                    onTap: () => _exportAndShare(
                        () => exportExpensesToCsv(
                            from: _exportPeriod?.from, to: _exportPeriod?.to),
                        'Finance Tracker — Expenses'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.download),
                    title: const Text('Download investments (CSV)'),
                    enabled: !_isWorking,
                    onTap: () => _exportAndShare(
                        () => exportInvestmentsToCsv(
                            from: _exportPeriod?.from, to: _exportPeriod?.to),
                        'Finance Tracker — Investments'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.table_view),
                    title: const Text('Download everything (Excel)'),
                    subtitle: const Text(
                        'Transactions, categories, months and investments '
                        'as sheets'),
                    enabled: !_isWorking,
                    onTap: () => _exportAndShare(
                        () => ExcelExport.writeEverything(
                            from: _exportPeriod?.from,
                            to: _exportPeriod?.to,
                            periodLabel: _exportPeriod?.label),
                        'Finance Tracker — Excel export'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.download),
                    title: const Text('Download full data (JSON)'),
                    enabled: !_isWorking,
                    // With database encryption on this file is sealed with
                    // the device key, so it only opens on this phone.
                    onTap: () => _exportAndShare(
                        _backupService.writeJsonBackupFile,
                        'Finance Tracker — Full Backup',
                        offDevice: !_dbEncrypted),
                  ),
                  ListTile(
                    leading: const Icon(Icons.ios_share),
                    title: const Text('Download encrypted backup'),
                    enabled: !_isWorking,
                    onTap: () async {
                      final pass = await _promptPassphrase(context,
                          title: 'Encrypt backup',
                          action: 'Encrypt',
                          confirm: true);
                      if (pass == null) return;
                      await _exportAndShare(
                          () => _backupService.writeEncryptedBackup(pass),
                          'Finance Tracker — Encrypted Backup',
                          offDevice: true);
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.upload_file),
                    title: const Text('Import from CSV'),
                    enabled: !_isWorking,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ImportScreen()),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Rarely needed, so folded away: the on-device JSON copy the
            // app also keeps by itself each day, and passphrase-sealed
            // files made by hand.
            Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: const Icon(Icons.tune),
                title: const Text('More options'),
                subtitle: const Text(
                    'A copy on this phone, verifying it, sealed backups'),
                shape: const Border(),
                collapsedShape: const Border(),
                children: [
                  ListTile(
                    leading: const Icon(Icons.save_alt),
                    title: const Text('Back up locally (JSON)'),
                    enabled: !_isWorking,
                    // writeJsonBackupFile, not backupToJson: it applies the
                    // device key when at-rest encryption is on, so this can't
                    // leave a readable copy of everything on disk.
                    onTap: () => _runTask(_backupService.writeJsonBackupFile,
                        'Local JSON backup created'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.restore),
                    title: const Text('Restore from local JSON'),
                    enabled: !_isWorking,
                    onTap: () => _restore(
                        ({bool allowEmpty = false}) => _backupService
                            .restoreFromJson(allowEmpty: allowEmpty),
                        'Restored from local JSON'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.fact_check_outlined),
                    title: const Text('Verify last backup'),
                    subtitle: const Text(
                        'Checks it opens, decrypts, and every row is intact'),
                    enabled: !_isWorking,
                    onTap: _verifyBackup,
                  ),
                  ListTile(
                    leading: const Icon(Icons.lock),
                    title: const Text('Create encrypted backup (JSON)'),
                    enabled: !_isWorking,
                    onTap: () async {
                      final pass = await _promptPassphrase(context,
                          title: 'Encrypt backup',
                          action: 'Encrypt',
                          confirm: true);
                      if (pass == null) return;
                      await _runTask(
                          () => _backupService.writeEncryptedBackup(pass),
                          'Encrypted backup created');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.lock_open),
                    title: const Text('Restore encrypted backup'),
                    enabled: !_isWorking,
                    onTap: () async {
                      if (!await _confirmRestore(context)) return;
                      if (!context.mounted) return;
                      final pass = await _promptPassphrase(context,
                          title: 'Restore encrypted backup', action: 'Restore');
                      if (pass == null) return;
                      await _runTask(() async {
                        try {
                          await _backupService.restoreFromEncryptedFile(pass);
                        } on EmptyBackupException catch (e) {
                          if (!context.mounted ||
                              !await _confirmEmptyRestore(context, e.message)) {
                            throw _cancelled;
                          }
                          await _backupService.restoreFromEncryptedFile(pass,
                              allowEmpty: true);
                        }
                      }, 'Restored from encrypted backup');
                    },
                  ),
                ],
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
