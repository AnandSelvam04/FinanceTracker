import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/account_provider.dart';
import '../providers/settings_provider.dart';
import '../services/notification_service.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AccountProvider>().fetchAccounts();
    });
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
