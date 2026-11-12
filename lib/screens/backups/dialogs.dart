part of '../backups_screen.dart';

/// A restore, parameterised by whether the user has already agreed to apply a
/// backup that contains no rows.
typedef _RestoreTask = Future<void> Function({bool allowEmpty});

/// A restore from a backup that may be passphrase-protected.
typedef _ProtectedRestoreTask = Future<void> Function(
    {bool allowEmpty, String? passphrase});

/// Unwinds a task the user backed out of part-way through, so [_runTask]
/// reports neither success nor an error.
class _Cancelled implements Exception {
  const _Cancelled();
}

/// Minimum length when *setting* a backup passphrase. Encrypted backups are
/// shared off-device, so the passphrase is their only protection.
const _minPassphraseLength = 12;

/// Steps to a month (or, with [yearOnly], a year) and confirms it. Starts
/// on [start].
Future<(int, int)?> _pickMonthOrYear(BuildContext context, DateTime start,
    {required bool yearOnly}) {
  var year = start.year;
  var month = start.month;
  return showDialog<(int, int)>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(yearOnly ? 'Which year?' : 'Which month?'),
      content: MonthSelector(
        initialYear: year,
        initialMonth: month,
        yearOnly: yearOnly,
        onChanged: (y, m) {
          year = y;
          month = m;
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, (year, month)),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Second confirmation, shown only when the backup parsed cleanly but has no
/// rows at all. The generic "Replace all data?" prompt isn't enough here —
/// the user thinks they are restoring something.
Future<bool> _confirmEmptyRestore(BuildContext context, String detail) async {
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
          child: Text('Erase everything',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Restore replaces all current data, so make the user confirm.
Future<bool> _confirmRestore(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Replace all data?'),
      content: const Text(
          'Restoring will delete everything currently in the app and replace it with the backup. This cannot be undone.\n\n'
          'Receipt photos are not part of a backup. Transactions keep the photos that are already on this phone; on a new phone they come back without them.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Replace',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
        ),
      ],
    ),
  );
  return ok == true;
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

String _mimeFor(String path) => path.endsWith('.json')
    ? 'application/json'
    : path.endsWith('.xlsx')
        ? ExcelExport.mimeType
        : 'text/csv';

/// Prompts for a passphrase. When [confirm] is set, requires it to be typed
/// twice and warns that a lost passphrase is unrecoverable. Returns null if
/// the user cancels.
Future<String?> _promptPassphrase(BuildContext context,
    {required String title,
    required String action,
    String? message,
    bool confirm = false}) async {
  final controller = TextEditingController();
  final confirmController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  // DisposeWithRoute disposes the controllers once the dialog has closed.
  // They hold a backup passphrase, so they must not outlive it.
  return showDialog<String>(
    context: context,
    builder: (ctx) => DisposeWithRoute(
      notifiers: [controller, confirmController],
      child: AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(message,
                      style: const TextStyle(fontSize: FontSizes.body)),
                ),
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
                  validator: (v) =>
                      v != controller.text ? 'Passphrases do not match' : null,
                ),
              if (confirm)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'If you forget this passphrase, the backup cannot be recovered.',
                    style: TextStyle(
                        fontSize: FontSizes.caption,
                        color: mutedTextColor(context)),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, controller.text);
              }
            },
            child: Text(action),
          ),
        ],
      ),
    ),
  );
}

String _prettyTable(String table) {
  switch (table) {
    case 'expenses':
      return 'Transactions';
    case 'recurring_rules':
      return 'Recurring rules';
    default:
      return '${table[0].toUpperCase()}${table.substring(1)}';
  }
}

/// Shows when a backup last left the phone, warning if it's stale (>7 days)
/// or has never happened. The daily on-device backup doesn't count: it is
/// lost together with the phone.
class _LastBackupBanner extends StatelessWidget {
  final DateTime? time;
  const _LastBackupBanner({required this.time});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final stale =
        time == null || now.difference(time!) > const Duration(days: 7);
    final color = stale ? warningColor(context) : incomeColor(context);

    String label;
    if (time == null) {
      label = 'Nothing is backed up off this phone yet — back up to Drive or '
          'download a backup so a lost phone doesn\'t take your data with it.';
    } else {
      final d = now.difference(time!);
      final ago = d.inDays >= 1
          ? (d.inDays == 1 ? '1 day ago' : '${d.inDays} days ago')
          : d.inHours >= 1
              ? (d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago')
              : 'just now';
      label = 'Last backup off this phone: $ago';
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
