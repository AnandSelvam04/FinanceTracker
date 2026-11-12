part of '../home_screen.dart';

/// Quick navigation shortcuts on the dashboard for destinations otherwise a
/// couple of taps away under More. Which ones show, and in what order, is the
/// user's choice (More → Customise home); Investments, Cards and Import SMS
/// by default. Import SMS only shows while SMS reading is switched on, so
/// the shortcut never leads to a screen that can only report it is off.
/// Everything stays listed under More as well; this is just a faster path.
class _ShortcutsRow extends StatelessWidget {
  const _ShortcutsRow();

  // Each shortcut wears its destination's own colour (the one it has under
  // More), so they read as separate destinations at a glance.
  static const _screens = <String, Widget>{
    DashboardLayout.investments: InvestmentsScreen(),
    // Credit cards have their own screen — spend by period, limit and
    // bills — rather than a section here, to keep the dashboard clear.
    DashboardLayout.cards: CreditCardsScreen(),
    DashboardLayout.reports: MonthlySummaryScreen(),
    DashboardLayout.accounts: AccountsScreen(),
    DashboardLayout.goals: GoalsScreen(),
    DashboardLayout.calendar: SpendingCalendarScreen(),
    DashboardLayout.loans: LoansScreen(),
    DashboardLayout.recurring: RecurringScreen(),
    DashboardLayout.cashflow: CashflowScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final ids = [
      for (final id in settings.homeShortcuts)
        if (id != DashboardLayout.sms || settings.smsImportEnabled) id,
    ];
    if (ids.isEmpty) return const SizedBox.shrink();
    // Four across leaves no room for an icon beside its label on a phone;
    // stack them instead.
    final compact = ids.length > 3;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          for (final (i, id) in ids.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: id == DashboardLayout.sms
                  ? _SmsShortcut(compact: compact)
                  : _ShortcutButton(
                      icon: Destinations.shortcuts[id]!.icon,
                      label: DashboardLayout.shortcutLabels[id]!,
                      accent: Destinations.shortcuts[id]!.color,
                      compact: compact,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => _screens[id]!),
                      ),
                    ),
            ),
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
  final bool compact;
  const _SmsShortcut({this.compact = false});

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
      icon: Destinations.sms.icon,
      label: 'Import SMS',
      accent: Destinations.sms.color,
      badge: _pending,
      compact: widget.compact,
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

  /// Icon above the label rather than beside it, for a row of four.
  final bool compact;
  const _ShortcutButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.badge = 0,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    // A soft tint of the accent as fill, the accent itself for icon and text,
    // so each shortcut carries its own color without shouting.
    final fill = destinationFill(context, accent);
    final foreground = destinationForeground(context, accent);
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
          padding: EdgeInsets.symmetric(
              vertical: compact ? 10 : 12, horizontal: compact ? 6 : 12),
          child: Flex(
            direction: compact ? Axis.vertical : Axis.horizontal,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text(badge > 99 ? '99+' : '$badge'),
                child: Icon(icon, size: 20, color: foreground),
              ),
              SizedBox(width: compact ? 0 : 8, height: compact ? 4 : 0),
              if (compact)
                // Shrinks to fit rather than being cut: a quarter of a phone
                // is narrower than "Investments".
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                )
              else
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
                      onPressed: () {
                        Haptics.light();
                        onQuickAdd(template);
                      },
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
    return ListTile(
      leading: IconBadge(icon: icon, color: color),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}
