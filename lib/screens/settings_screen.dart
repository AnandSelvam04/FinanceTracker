import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
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
  static const _lockOptions = <int, String>{
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
  Future<void> _toggleEncryption(bool enable, AppLocalizations l) async {
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
          content: Text(now ? l.encryptionEnabled : l.encryptionDisabled)));
    } catch (e) {
      final now = await DBService().isEncryptionEnabled();
      if (!mounted) return;
      setState(() => _encryptionEnabled = now);
      messenger.showSnackBar(
          SnackBar(content: Text(l.errorWithDetails('$e'))));
    } finally {
      if (mounted) setState(() => _encryptionBusy = false);
    }
  }

  String _themeLabel(ThemeMode mode, AppLocalizations l) {
    switch (mode) {
      case ThemeMode.light:
        return l.themeLight;
      case ThemeMode.dark:
        return l.themeDark;
      case ThemeMode.system:
        return l.themeSystem;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: Consumer2<SettingsProvider, AccountProvider>(
        builder: (context, settings, accounts, _) {
          return ListView(
            padding: scrollPadding(context, all: 0),
            children: [
              _SectionHeader(l.sectionGeneral),
              ListTile(
                leading: const Icon(Icons.currency_exchange),
                title: Text(l.currencySymbol),
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
                title: Text(l.theme),
                trailing: DropdownButton<ThemeMode>(
                  value: settings.themeMode,
                  items: ThemeMode.values
                      .map((m) => DropdownMenuItem(
                          value: m, child: Text(_themeLabel(m, l))))
                      .toList(),
                  onChanged: (m) {
                    if (m != null) settings.setThemeMode(m);
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet),
                title: Text(l.defaultAccount),
                subtitle: Text(l.defaultAccountSubtitle),
                trailing: DropdownButton<int?>(
                  value: accounts.accountById(settings.defaultAccountId) != null
                      ? settings.defaultAccountId
                      : null,
                  hint: Text(l.none),
                  items: [
                    DropdownMenuItem<int?>(
                        value: null, child: Text(l.none)),
                    ...accounts.accounts.map((a) =>
                        DropdownMenuItem<int?>(
                            value: a.id, child: Text(a.name))),
                  ],
                  onChanged: (id) => settings.setDefaultAccountId(id),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active),
                title: Text(l.budgetBillAlerts),
                subtitle: Text(l.budgetBillAlertsSubtitle),
                value: settings.alertsEnabled,
                onChanged: settings.setAlertsEnabled,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.notifications),
                title: Text(l.pushNotifications),
                subtitle: Text(l.pushNotificationsSubtitle),
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
              _SectionHeader(l.sectionSecurity),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(l.autoLock),
                subtitle: Text(l.autoLockSubtitle),
                trailing: DropdownButton<int>(
                  value: _lockOptions.containsKey(settings.lockTimeoutSeconds)
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
                title: Text(l.encryptDatabase),
                subtitle: Text(_encryptionBusy
                    ? (_encryptionEnabled ? l.decrypting : l.encrypting)
                    : l.encryptDatabaseSubtitle),
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
