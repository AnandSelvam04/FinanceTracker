part of '../home_screen.dart';

/// Quick navigation shortcuts on the dashboard for destinations otherwise a
/// couple of taps away under More: Investments always, and Import from SMS
/// when SMS reading is switched on (so the shortcut never leads to a screen
/// that can only report it is off). Both stay listed under More as well; this
/// is just a faster path from the home screen.
class _ShortcutsRow extends StatelessWidget {
  const _ShortcutsRow();

  @override
  Widget build(BuildContext context) {
    final smsEnabled = context.watch<SettingsProvider>().smsImportEnabled;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          Expanded(
            child: _ShortcutButton(
              icon: Icons.trending_up,
              label: 'Investments',
              // Distinct accents (not one shared container) so the shortcuts
              // read as separate destinations at a glance.
              accent: const Color(0xFF00897B), // teal
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const InvestmentsScreen()),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Credit cards have their own screen — spend by period, limit and
          // bills — rather than a section here, to keep the dashboard clear.
          Expanded(
            child: _ShortcutButton(
              icon: Icons.credit_card,
              label: 'Cards',
              accent: const Color(0xFF1E6FD9), // blue
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const CreditCardsScreen()),
              ),
            ),
          ),
          if (smsEnabled) ...[
            const SizedBox(width: 8),
            const Expanded(child: _SmsShortcut()),
          ],
        ],
      ),
    );
  }
}

/// The Import SMS shortcut, badged with how many new bank alerts are waiting
/// since the last review — so the queue announces itself instead of relying
/// on the user remembering to open it. Recounted when the app comes back to
/// the foreground and after returning from the review screen.
class _SmsShortcut extends StatefulWidget {
  const _SmsShortcut();

  @override
  State<_SmsShortcut> createState() => _SmsShortcutState();
}

class _SmsShortcutState extends State<_SmsShortcut> {
  int _pending = 0;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final count = await SmsService.pendingCount();
    if (mounted && count != _pending) setState(() => _pending = count);
  }

  @override
  Widget build(BuildContext context) {
    return _ShortcutButton(
      icon: Icons.sms,
      label: 'Import SMS',
      accent: const Color(0xFF6A3DE8), // violet
      badge: _pending,
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SmsReviewScreen()),
        );
        await _refresh();
      },
    );
  }
}

/// One tappable shortcut chip used in [_ShortcutsRow].
class _ShortcutButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  /// A count shown on the icon (new items waiting); hidden at zero.
  final int badge;
  const _ShortcutButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // A soft tint of the accent as fill, the accent itself for icon and text,
    // so each shortcut carries its own color without shouting.
    final fill = accent.withValues(alpha: dark ? 0.24 : 0.14);
    final foreground = dark ? Color.lerp(accent, Colors.white, 0.4)! : accent;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accent.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text(badge > 99 ? '99+' : '$badge'),
                child: Icon(icon, size: 20, color: foreground),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal row of saved templates for one-tap adding from the dashboard.
class _QuickAddRow extends StatelessWidget {
  final Future<void> Function(TxTemplate template) onQuickAdd;
  const _QuickAddRow({required this.onQuickAdd});

  /// Confirms before dropping a saved quick-add shortcut. Deleting the
  /// template only removes the one-tap shortcut — transactions already added
  /// from it are untouched.
  Future<void> _confirmDelete(BuildContext context, TemplateProvider provider,
      TxTemplate template) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete quick add?'),
        content: Text('Remove "${template.name}" from your quick-add '
            'shortcuts? Transactions you already added are not affected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await provider.deleteTemplate(template.id!);
    messenger.showSnackBar(
      SnackBar(content: Text('Deleted quick add "${template.name}"')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TemplateProvider>(
      builder: (context, provider, _) {
        final templates = provider.templates;
        if (templates.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'QUICK ADD',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                  color: mutedTextColor(context),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: templates.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final template = templates[index];
                    // Tap the chip to add; the delete "x" removes the shortcut
                    // (after a confirm), so a quick-add saved by mistake or no
                    // longer used can be cleared.
                    return InputChip(
                      avatar: const Icon(Icons.bolt, size: 18),
                      label: Text(
                          '${template.name} · ${formatMoneyRounded(template.amount)}'),
                      onPressed: () => onQuickAdd(template),
                      onDeleted: template.id == null
                          ? null
                          : () => _confirmDelete(context, provider, template),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      deleteButtonTooltipMessage: 'Delete quick add',
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One row of the add sheet: a tinted icon badge, a title and a hint of what
/// the option does — the same badge style as the More menu.
class _AddOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AddOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: dark ? 0.24 : 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}
