import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/app_lock.dart';
import '../services/db_service.dart';
import '../services/notification_service.dart';
import '../services/sms_service.dart';
import '../utils/build_info.dart';
import '../utils/currency_format.dart';
import '../utils/insets.dart';
import '../widgets/whats_new_sheet.dart';
import '../widgets/section_header.dart';
import '../providers/reload_all.dart';
import '../services/backup_service.dart';
import '../utils/error_message.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;
import '../utils/dimens.dart';

class SettingsScreen extends StatefulWidget {
  /// The title of a setting to scroll to and highlight (from a search on
  /// More), or null.
  final String? highlight;

  const SettingsScreen({super.key, this.highlight});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Default time for a newly enabled daily reminder: 9 PM, after most of the
  /// day's spending.
  static const _defaultReminderMinutes = 21 * 60;

  static String _timeLabel(BuildContext context, int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);

  /// Asks for the reminder time and turns the reminder on at it.
  Future<void> _chooseReminderTime(SettingsProvider settings) async {
    final current = settings.dailyReminderMinutes ?? _defaultReminderMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: 'Remind me every day at',
    );
    if (picked == null) return;
    await settings.setDailyReminderMinutes(picked.hour * 60 + picked.minute);
    await NotificationService.instance.requestPermission();
  }

  /// Auto-lock delay choices, keyed by their value in seconds.
  static Map<int, String> get _lockOptions => {
        0: 'Immediately',
        15: 'After 15 seconds',
        30: 'After 30 seconds',
        60: 'After 1 minute',
        300: 'After 5 minutes',
      };

  bool _encryptionEnabled = false;
  bool _encryptionBusy = false;

  /// Warns before switching base currency while foreign-currency accounts
  /// exist.
  ///
  /// Each account stores a `rate` meaning "base units per 1 unit of this
  /// account's currency". Changing the base currency silently invalidates
  /// every one of those rates — net worth, budgets and all converted totals
  /// quietly become wrong — and an account held in the *new* base currency
  /// keeps a rate that is no longer 1.0. Nothing here can recompute them
  /// (the app has no FX feed), so the honest move is to say so and point the
  /// user at the accounts they need to fix.
  Future<bool> _confirmCurrencyChange(String next) async {
    final accounts = context.read<AccountProvider>().accounts;
    final affected = accounts.where((a) => a.rate != 1.0).toList();
    if (affected.isEmpty) return true;

    final names = affected.map((a) => '${a.name} (${a.symbol})').join(', ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update exchange rates too?'),
        content: Text(
          'Exchange rates are stored relative to the current base currency '
          '(${CurrencyFormat.symbol}). Switching to $next leaves these '
          'accounts with rates that no longer mean anything:\n\n$names\n\n'
          'Balances and totals will be wrong until you edit each account\'s '
          'rate to be against $next.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Change anyway')),
        ],
      ),
    );
    return ok == true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      unawaited(context.read<AccountProvider>().fetchAccounts());
      final enabled = await DBService().isEncryptionEnabled();
      if (mounted) setState(() => _encryptionEnabled = enabled);
    });
  }

  /// Explains what encryption changes about backups before it is switched
  /// on: the key lives only on this phone, so anything sealed with it can't
  /// be opened after a reset or on a new phone.
  Future<bool> _confirmEncryption() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Encrypt the database?'),
        content: const Text(
            'The key is kept only on this phone. The automatic on-device '
            'backup is sealed with it too, so it can\'t be opened after a '
            'reset or on another phone.\n\n'
            'Drive backups will ask for a passphrase instead — keep it safe, '
            'it is the only way to restore on a new phone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Encrypt')),
        ],
      ),
    );
    return ok == true;
  }

  /// Toggles at-rest DB encryption. The migration is verify-and-rollback, so
  /// data is preserved even if it fails; on error we surface it and leave the
  /// switch in its real state.
  Future<bool> _confirmDecryption() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove encryption?'),
        content: const Text(
            'Your data stays on this phone but is stored unencrypted, so '
            'anyone who can read the phone\'s storage can read it. The app '
            'lock still applies.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep encrypted')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _toggleEncryption(bool enable) async {
    if (enable && !await _confirmEncryption()) return;
    if (!enable && !await _confirmDecryption()) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final expenses = context.read<ExpenseProvider>();
    final accounts = context.read<AccountProvider>();
    setState(() => _encryptionBusy = true);
    try {
      if (enable) {
        await DBService().enableEncryption();
      } else {
        await DBService().disableEncryption();
      }
      // The database file was recreated; refresh in-memory views.
      await expenses.reloadLoadedYears();
      await accounts.fetchAccounts();
      final now = await DBService().isEncryptionEnabled();
      if (!mounted) return;
      setState(() => _encryptionEnabled = now);
      messenger.showSnackBar(SnackBar(
          content: Text(
              now ? 'Database encrypted' : 'Database encryption removed')));
    } catch (e, st) {
      final now = await DBService().isEncryptionEnabled();
      if (!mounted) return;
      setState(() => _encryptionEnabled = now);
      messenger.showSnackBar(SnackBar(
          content: Text(friendlyError(
              _encryptionEnabled
                  ? "Couldn't remove the encryption"
                  : "Couldn't encrypt the database",
              e,
              st))));
    } finally {
      if (mounted) setState(() => _encryptionBusy = false);
    }
  }

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System default';
    }
  }

  @override
  Widget build(BuildContext context) {
    SectionHeader header(String title) => SectionHeader(title,
        padding:
            const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.xs));
    // Each setting search can jump to, by its title.
    Widget spot(String title, Widget tile) => _Spot(
          active: widget.highlight == title,
          child: tile,
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Consumer2<SettingsProvider, AccountProvider>(
        builder: (context, settings, accounts, _) {
          // A Column, not a ListView: every row is built, so a search result
          // far down the page can be scrolled to and highlighted.
          return SingleChildScrollView(
            padding: scrollPadding(context, all: 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header('General'),
                spot(
                  'Currency symbol',
                  ListTile(
                    leading: const Icon(Icons.currency_exchange),
                    title: const Text('Currency symbol'),
                    trailing: DropdownButton<String>(
                      value: SettingsProvider.currencyOptions
                              .contains(settings.currencySymbol)
                          ? settings.currencySymbol
                          : null,
                      hint: Text(settings.currencySymbol),
                      items: SettingsProvider.currencyOptions
                          .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (v) async {
                        if (v == null || v == settings.currencySymbol) return;
                        if (!await _confirmCurrencyChange(v)) return;
                        await settings.setCurrencySymbol(v);
                      },
                    ),
                  ),
                ),
                spot(
                  'Default account',
                  ListTile(
                    leading: const Icon(Icons.account_balance_wallet),
                    title: const Text('Default account'),
                    subtitle: const Text('Preselected for new transactions'),
                    trailing: ConstrainedBox(
                      // Capped so a long account name ellipsizes instead of
                      // squeezing the title out of the tile.
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.4),
                      child: DropdownButton<int?>(
                        isExpanded: true,
                        value:
                            accounts.accountById(settings.defaultAccountId) !=
                                    null
                                ? settings.defaultAccountId
                                : null,
                        hint: const Text('None'),
                        items: [
                          const DropdownMenuItem<int?>(
                              value: null, child: Text('None')),
                          ...accounts.pickable([settings.defaultAccountId]).map(
                              (a) => DropdownMenuItem<int?>(
                                  value: a.id,
                                  child: Text(a.name,
                                      overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: (id) => settings.setDefaultAccountId(id),
                      ),
                    ),
                  ),
                ),
                const Divider(),
                header('Appearance'),
                spot(
                  'Theme',
                  ListTile(
                    leading: const Icon(Icons.brightness_6),
                    title: const Text('Theme'),
                    trailing: DropdownButton<ThemeMode>(
                      value: settings.themeMode,
                      items: ThemeMode.values
                          .map((m) => DropdownMenuItem(
                              value: m, child: Text(_themeLabel(m))))
                          .toList(),
                      onChanged: (m) {
                        if (m != null) unawaited(settings.setThemeMode(m));
                      },
                    ),
                  ),
                ),
                spot(
                  'Theme',
                  SwitchListTile(
                    secondary: const Icon(Icons.contrast),
                    title: const Text('True black dark theme'),
                    subtitle: const Text(
                        'Pure black backgrounds in dark mode — easier on OLED '
                        'screens and the battery'),
                    value: settings.trueBlack,
                    onChanged: (v) => settings.setTrueBlack(v),
                  ),
                ),
                spot(
                  'Accent colour',
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('Accent colour'),
                    subtitle: Wrap(
                      spacing: 2,
                      children: [
                        for (final (i, c)
                            in SettingsProvider.seedOptions.indexed)
                          _AccentSwatch(
                            color: c,
                            name: _accentNames[i],
                            selected: !settings.useWallpaperAccent &&
                                settings.seedColor.toARGB32() == c.toARGB32(),
                            onTap: () => settings.setSeedColor(c),
                          ),
                      ],
                    ),
                  ),
                ),
                // Only where the phone offers a wallpaper colour (Android 12+).
                if (settings.wallpaperAccent != null)
                  spot(
                    'Accent colour',
                    SwitchListTile(
                      secondary: const Icon(Icons.wallpaper),
                      title: const Text('Match my wallpaper'),
                      subtitle: const Text(
                          'Take the accent colour from the phone\'s wallpaper'),
                      value: settings.useWallpaperAccent,
                      onChanged: (v) => settings.setUseWallpaperAccent(v),
                    ),
                  ),
                const Divider(),
                header('Budgets & alerts'),
                spot(
                  'Roll over unspent budget',
                  SwitchListTile(
                    secondary: const Icon(Icons.redo),
                    title: const Text('Roll over unspent budget'),
                    subtitle: const Text(
                        'Carry what is left of a budget (or its overspend) '
                        'into the next month\'s cap'),
                    value: settings.budgetRollover,
                    onChanged: settings.setBudgetRollover,
                  ),
                ),
                spot(
                  'Budget & bill alerts',
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_active),
                    title: const Text('Budget & bill alerts'),
                    subtitle: const Text(
                        'Show dashboard warnings for budgets and due bills'),
                    value: settings.alertsEnabled,
                    onChanged: settings.setAlertsEnabled,
                  ),
                ),
                const Divider(),
                header('Notifications'),
                spot(
                  'Push notifications',
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications),
                    title: const Text('Push notifications'),
                    subtitle: const Text(
                        'Reminders before bills are due and budget-limit '
                        'alerts'),
                    value: settings.notificationsEnabled,
                    onChanged: (v) async {
                      if (!v) {
                        await settings.setNotificationsEnabled(false);
                        await NotificationService.instance.cancelAll();
                        return;
                      }
                      // On only if Android lets the app post them.
                      if (!await _askNotifications()) return;
                      await settings.setNotificationsEnabled(true);
                    },
                  ),
                ),
                spot(
                  'Daily reminder',
                  // A plain tile with its own switch, so tapping the row
                  // changes the time while the switch turns it on and off.
                  ListTile(
                    enabled: settings.notificationsEnabled,
                    leading: const Icon(Icons.edit_calendar_outlined),
                    title: const Text('Daily reminder'),
                    subtitle: Text(settings.dailyReminderMinutes == null
                        ? 'A nudge each day to log your spending'
                        : 'Every day at '
                            '${_timeLabel(context, settings.dailyReminderMinutes!)}'
                            ', skipped once you\'ve added something that day'),
                    onTap: settings.dailyReminderMinutes == null
                        ? null
                        : () => _chooseReminderTime(settings),
                    trailing: Switch(
                      value: settings.dailyReminderMinutes != null,
                      // It is a notification, so it follows the master
                      // switch.
                      onChanged: settings.notificationsEnabled
                          ? (v) => v
                              ? _chooseReminderTime(settings)
                              : settings.setDailyReminderMinutes(null)
                          : null,
                    ),
                  ),
                ),
                if (SmsService.isSupported) ...[
                  const Divider(),
                  header('SMS import'),
                  spot(
                    'Read SMS for transactions',
                    SwitchListTile(
                      secondary: const Icon(Icons.sms),
                      title: const Text('Read SMS for transactions'),
                      subtitle: const Text(
                          'Find bank alerts since you last reviewed them. '
                          'Messages are read on this device and never sent '
                          'anywhere; nothing is recorded without your '
                          'confirmation.'),
                      isThreeLine: true,
                      value: settings.smsImportEnabled,
                      onChanged: (v) async {
                        if (!v) {
                          await settings.setSmsImportEnabled(false);
                          return;
                        }
                        // Ask straight away rather than on the first scan,
                        // so turning it on either works or visibly does not.
                        await settings.setSmsImportEnabled(true);
                        if (!await SmsService.requestPermission()) {
                          await settings.setSmsImportEnabled(false);
                          _permissionRefused('read your SMS');
                        }
                      },
                    ),
                  ),
                  if (settings.smsImportEnabled)
                    spot(
                      'Read SMS for transactions',
                      SwitchListTile(
                        secondary: const Icon(Icons.mark_chat_unread_outlined),
                        title: const Text('Notify me as transactions arrive'),
                        subtitle: const Text(
                            'When a bank alert comes in, a notification '
                            'offers to review and add it — even while the '
                            'app is closed. Nothing is recorded until you '
                            'confirm.'),
                        isThreeLine: true,
                        value: settings.smsAutoCapture,
                        onChanged: (v) async {
                          if (v) {
                            // Receiving needs its own permission (asked
                            // together with reading), and the notification
                            // needs one too.
                            if (!await SmsService.requestPermission()) {
                              _permissionRefused('read your SMS');
                              return;
                            }
                            if (!await _askNotifications()) return;
                          }
                          await settings.setSmsAutoCapture(v);
                        },
                      ),
                    ),
                ],
                const Divider(),
                header('Security'),
                spot(
                  'App lock',
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint),
                    title: const Text('App lock'),
                    subtitle: const Text(
                        'Require biometrics or device PIN on launch'),
                    value: settings.appLockEnabled,
                    onChanged: (on) => setAppLockChecked(context, on),
                  ),
                ),
                spot(
                  'App lock',
                  ListTile(
                    // Only means something while the lock is on.
                    enabled: settings.appLockEnabled,
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('Auto-lock'),
                    subtitle: const Text('Re-lock after being away this long'),
                    trailing: DropdownButton<int>(
                      value:
                          _lockOptions.containsKey(settings.lockTimeoutSeconds)
                              ? settings.lockTimeoutSeconds
                              : null,
                      hint: Text('${settings.lockTimeoutSeconds}s'),
                      items: _lockOptions.entries
                          .map((e) => DropdownMenuItem(
                              value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: !settings.appLockEnabled
                          ? null
                          : (v) {
                              if (v != null) {
                                unawaited(settings.setLockTimeoutSeconds(v));
                              }
                            },
                    ),
                  ),
                ),
                spot(
                  'Encrypt database',
                  SwitchListTile(
                    secondary: _encryptionBusy
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.enhanced_encryption),
                    title: const Text('Encrypt database'),
                    subtitle: Text(_encryptionBusy
                        ? (_encryptionEnabled
                            ? 'Removing encryption…'
                            : 'Encrypting database…')
                        : 'Protect on-device data with a device-secured key'),
                    value: _encryptionEnabled,
                    onChanged:
                        _encryptionBusy ? null : (v) => _toggleEncryption(v),
                  ),
                ),
                const Divider(),
                header('Data'),
                spot(
                  'Erase all data',
                  ListTile(
                    leading: Icon(Icons.delete_forever_outlined,
                        color: Theme.of(context).colorScheme.error),
                    title: Text('Erase all data',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    subtitle: const Text(
                        'Delete every transaction, account, budget and '
                        'investment, to start afresh. Settings stay.'),
                    onTap: _eraseAll,
                  ),
                ),
                const Divider(),
                header('About'),
                spot(
                  "What's new",
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Version'),
                    subtitle: Text(BuildInfo.label),
                    // Identifies the exact build, so a screenshot or bug
                    // report can be tied back to a commit. Tap to copy.
                    onTap: () {
                      unawaited(Clipboard.setData(
                          ClipboardData(text: BuildInfo.label)));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Version copied')),
                      );
                    },
                  ),
                ),
                spot(
                  "What's new",
                  ListTile(
                    leading: const Icon(Icons.new_releases_outlined),
                    title: const Text("What's new"),
                    subtitle: const Text('What changed in this version'),
                    onTap: () => showWhatsNewSheet(context),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static const _accentNames = [
    'Indigo',
    'Green',
    'Purple',
    'Pink',
    'Orange',
    'Teal',
    'Slate',
  ];

  /// Asks for the notification permission; when Android refuses, says so and
  /// answers false, so the switch that asked stays off.
  Future<bool> _askNotifications() async {
    if (await NotificationService.instance.requestPermission()) return true;
    _permissionRefused('show notifications');
    return false;
  }

  /// Explains a refused permission, with a way to Android's settings.
  void _permissionRefused(String what) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('The app isn\'t allowed to $what, so this stays off.'),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Settings',
        onPressed: () => unawaited(openAppSettings()),
      ),
    ));
  }

  /// Erases everything after a confirmation, with Undo.
  Future<void> _eraseAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erase all data?'),
        content: const Text(
            'Every transaction, account, budget, investment, goal and '
            'recurring rule is deleted. Your settings stay.\n\n'
            'A copy is kept on this phone until your next restore, so you '
            'can undo this from Backup & Export. Back up first if you may '
            'want this data on another phone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Erase everything')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final reload = dataReloader(context);
    final backups = BackupService();
    try {
      await backups.eraseAllData();
      await reload();
      messenger.showSnackBar(SnackBar(
        content: const Text('All data erased'),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await backups.undoRestore();
              await reload();
            } catch (e, st) {
              messenger.showSnackBar(SnackBar(
                  content: Text(
                      friendlyError("Couldn't bring the data back", e, st))));
            }
          },
        ),
      ));
    } catch (e, st) {
      messenger.showSnackBar(SnackBar(
          content: Text(friendlyError("Couldn't erase the data", e, st))));
    }
  }
}

/// A setting a search result points at: scrolled into view and briefly
/// tinted when [active], so it is obvious which row was meant.
class _Spot extends StatefulWidget {
  final bool active;
  final Widget child;

  const _Spot({required this.active, required this.child});

  @override
  State<_Spot> createState() => _SpotState();
}

class _SpotState extends State<_Spot> {
  bool _lit = false;
  Timer? _fade;

  @override
  void initState() {
    super.initState();
    if (!widget.active) return;
    _lit = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(Scrollable.ensureVisible(context,
          alignment: 0.3, duration: const Duration(milliseconds: 300)));
      _fade = Timer(const Duration(milliseconds: 1900), () {
        if (mounted) setState(() => _lit = false);
      });
    });
  }

  @override
  void dispose() {
    _fade?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      color: _lit
          ? scheme.primaryContainer.withValues(alpha: 0.6)
          : Colors.transparent,
      // The tile's ink draws on this, above the tint.
      child: Material(type: MaterialType.transparency, child: widget.child),
    );
  }
}

/// A tappable colour dot for the accent-colour picker, with a ring and check
/// when it is the active accent. The dot is 30px but the target a full 48dp,
/// and it is announced by its colour name.
class _AccentSwatch extends StatelessWidget {
  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _AccentSwatch({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$name accent',
      excludeSemantics: true,
      child: Tooltip(
        message: name,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: selected
                      ? Border.all(
                          color: Theme.of(context).colorScheme.onSurface,
                          width: 2)
                      : null,
                ),
                child: selected
                    ? const Icon(Icons.check, size: 18, color: Colors.white)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
