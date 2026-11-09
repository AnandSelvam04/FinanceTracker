part of '../sms_review_screen.dart';

class _EmptyState extends StatelessWidget {
  final bool permissionDenied;
  final String rangeLabel;
  final bool includeDismissed;
  final VoidCallback onRetry;
  const _EmptyState({
    required this.permissionDenied,
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
                onPressed: onRetry,
                child: Text(permissionDenied ? 'Grant permission' : 'Rescan'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The row above the queue that acts on every draft at once: select/clear all
/// and apply one account to the whole batch.
class _BulkActionBar extends StatelessWidget {
  final int total;
  final int selected;
  final VoidCallback onSelectAll;
  final VoidCallback onSelectNone;

  /// Null disables the button (no accounts to choose from).
  final VoidCallback? onSetAccount;

  /// Null disables the button (nothing selected, or an import is running).
  final VoidCallback? onDismissSelected;

  const _BulkActionBar({
    required this.total,
    required this.selected,
    required this.onSelectAll,
    required this.onSelectNone,
    required this.onSetAccount,
    required this.onDismissSelected,
  });

  @override
  Widget build(BuildContext context) {
    final allSelected = selected == total && total > 0;
    // Compact density and a scrollable action row keep the bar from
    // overflowing on a narrow screen once a third action is added.
    const compact = ButtonStyle(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
      child: Row(
        children: [
          TextButton.icon(
            style: compact,
            icon: Icon(
                allSelected ? Icons.check_box_outline_blank : Icons.select_all),
            label: Text(allSelected ? 'Clear all' : 'Select all'),
            onPressed: allSelected ? onSelectNone : onSelectAll,
          ),
          Text('$selected of $total',
              style: TextStyle(fontSize: 12, color: mutedTextColor(context))),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  TextButton.icon(
                    style: compact,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('Dismiss'),
                    onPressed: onDismissSelected,
                  ),
                  TextButton.icon(
                    style: compact,
                    icon: const Icon(Icons.account_balance_wallet_outlined,
                        size: 18),
                    label: const Text('Set account'),
                    onPressed: onSetAccount,
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
