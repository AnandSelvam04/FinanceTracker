part of '../sms_review_screen.dart';

class _EmptyState extends StatelessWidget {
  final bool permissionDenied;

  /// Asking again cannot help; only Android's settings or a reinstall can.
  final bool permissionBlocked;
  final String rangeLabel;
  final bool includeDismissed;
  final VoidCallback onRetry;
  const _EmptyState({
    required this.permissionDenied,
    required this.permissionBlocked,
    required this.rangeLabel,
    required this.includeDismissed,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final supported = SmsService.isSupported;
    final String message;
    if (!supported) {
      message = 'SMS import works on Android only.';
    } else if (permissionBlocked) {
      // The request is refused without a dialog ever showing, so "try again"
      // would just look broken. Say what is really holding it, and offer the
      // one screen that can sometimes release it.
      message = 'Android is holding the SMS permission back, so it cannot be '
          'granted from here. That happens when an app is installed from a '
          'file instead of a store: SMS is a restricted permission, and only '
          'the installer can release it.\n\nTo release it: open the SMS '
          'permission screen and tap the greyed-out "Allow" once, so Android '
          'shows its "Restricted setting" notice. Go back to App info, open '
          'the three-dot menu at the top right and choose "Allow restricted '
          'settings" (the entry appears only after that notice). Then set '
          'Permissions > SMS to Allow.\n\nIf the menu entry never appears, '
          'only reinstalling over USB with "adb install -g" can lift it. '
          'Everything else in the app works without it.';
    } else if (permissionDenied) {
      message = 'Finance Tracker needs permission to read SMS so it can find '
          'bank transaction alerts. Nothing is sent anywhere — messages are '
          'read on this device only.';
    } else {
      message = 'No new transactions found $rangeLabel. Messages you '
          'already imported${includeDismissed ? '' : ' or dismissed'} are not '
          'shown again.'
          '${includeDismissed ? '' : ' Widen the range or show dismissed '
              'messages from the toolbar.'}';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(permissionDenied ? Icons.lock_outline : Icons.sms_outlined,
                size: 48, color: mutedTextColor(context)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (supported) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: permissionBlocked
                    ? SmsService.openPermissionSettings
                    : onRetry,
                child: Text(permissionBlocked
                    ? 'Open app settings'
                    : permissionDenied
                        ? 'Grant permission'
                        : 'Rescan'),
              ),
              // Back from Android's settings with the permission allowed.
              if (permissionBlocked)
                TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

/// The bar above the queue: what the scan found, and the actions that work
/// on every ticked draft at once.
class _BulkActionBar extends StatelessWidget {
  final int total;
  final int selected;

  /// "since 10 Nov", "in the last 7 days" — the span that was scanned.
  final String rangeLabel;
  final VoidCallback onSelectAll;
  final VoidCallback onSelectNone;

  /// Null disables the button (nothing selected, or no accounts).
  final VoidCallback? onSetAccount;

  /// Null disables the button (nothing selected, or an import is running).
  final VoidCallback? onDismissSelected;

  const _BulkActionBar({
    required this.total,
    required this.selected,
    required this.rangeLabel,
    required this.onSelectAll,
    required this.onSelectNone,
    required this.onSetAccount,
    required this.onDismissSelected,
  });

  @override
  Widget build(BuildContext context) {
    final allSelected = selected == total && total > 0;
    const compact = ButtonStyle(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    // The checkbox lines up with the ones on the cards below it.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        children: [
          Checkbox(
            tristate: true,
            value: allSelected ? true : (selected == 0 ? false : null),
            onChanged: (_) => allSelected ? onSelectNone() : onSelectAll(),
          ),
          Expanded(
            flex: 2,
            child: Tooltip(
              message: allSelected ? 'Clear all' : 'Select all',
              child: InkWell(
                onTap: allSelected ? onSelectNone : onSelectAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$selected of $total selected',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('Found $rangeLabel',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: mutedTextColor(context))),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Scaled down rather than overflowing at a very large text size.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    style: compact,
                    onPressed: onDismissSelected,
                    child: const Text('Dismiss'),
                  ),
                  TextButton(
                    style: compact,
                    onPressed: onSetAccount,
                    child: const Text('Set account'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A one-line explanation under a draft's header — why it is unchecked, or
/// why it is being recorded as a transfer rather than as spending.
class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Notice({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 0, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }
}
