import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../services/db_service.dart';
import '../services/notification_service.dart';
import '../utils/insets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Auto-lock delays, labelled in the active locale.
  static Map<int, String> get _lockOptions => {
        0: 'Immediately',
        15: 'After 15 seconds',
        30: 'After 30 seconds',
        60: 'After 1 minute',
        300: 'After 5 minutes',
      };

  bool _encryptionEnabled = false;
  bool _encryptionBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      context.read<AccountProvider>().fetchAccounts();
      final enabled = await DBService().isEncryptionEnabled();
      if (mounted) setState(() => _encryptionEnabled = enabled);
    });
  }

  /// Toggles at-rest DB encryption. The migration is verify-and-rollback, so
  /// data is preserved even if it fails; on error we surface it and leave the
  /// switch in its real state.
  Future<void> _toggleEncryption(bool enable) async {
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
          content: Text(now ? 'Database encrypted' : 'Database encryption removed')));
    } catch (e) {
      final now = await DBService().isEncryptionEnabled();
      if (!mounted) return;
      setState(() => _encryptionEnabled = now);
      messenger.showSnackBar(
          SnackBar(content: Text('Error: $e')));
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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Consumer2<SettingsProvider, AccountProvider>(
        builder: (context, settings, accounts, _) {
          return ListView(
            padding: scrollPadding(context, all: 0),
            children: [
              _SectionHeader('General'),
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
                      .map((s) =>
                          DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) settings.setCurrencySymbol(v);
                  },
                ),
              ),
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
                    if (m != null) settings.setThemeMode(m);
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet),
                title: const Text('Default account'),
                subtitle: const Text('Preselected for new transactions'),
                trailing: DropdownButton<int?>(
                  value: accounts.accountById(settings.defaultAccountId) != null
                      ? settings.defaultAccountId
                      : null,
                  hint: const Text('None'),
                  items: [
                    DropdownMenuItem<int?>(
                        value: null, child: const Text('None')),
                    ...accounts.accounts.map((a) =>
                        DropdownMenuItem<int?>(
                            value: a.id, child: Text(a.name))),
                  ],
                  onChanged: (id) => settings.setDefaultAccountId(id),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active),
                title: const Text('Budget & bill alerts'),
                subtitle: const Text('Show dashboard warnings for budgets and due bills'),
                value: settings.alertsEnabled,
                onChanged: settings.setAlertsEnabled,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.notifications),
                title: const Text('Push notifications'),
                subtitle: const Text('Reminders before bills are due and budget-limit alerts'),
                value: settings.notificationsEnabled,
                onChanged: (v) async {
                  await settings.setNotificationsEnabled(v);
                  if (v) {
                    await NotificationService.instance.requestPermission();
                  } else {
                    await NotificationService.instance.cancelAll();
                  }
                },
              ),
              const Divider(),
              _SectionHeader('Security'),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Auto-lock'),
                subtitle: const Text('When app lock is on, re-lock after being away'),
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
                  onChanged: (v) {
                    if (v != null) settings.setLockTimeoutSeconds(v);
                  },
                ),
              ),
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
                    ? (_encryptionEnabled ? 'Removing encryption…' : 'Encrypting database…')
                    : 'Protect on-device data with a device-secured key'),
                value: _encryptionEnabled,
                onChanged: _encryptionBusy
                    ? null
                    : (v) => _toggleEncryption(v, l),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
