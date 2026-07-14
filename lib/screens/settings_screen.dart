import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/account_provider.dart';
import '../providers/settings_provider.dart';

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
            children: [
              const _SectionHeader('General'),
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
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('None')),
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
                subtitle: const Text(
                    'Show dashboard warnings for budgets and due bills'),
                value: settings.alertsEnabled,
                onChanged: settings.setAlertsEnabled,
              ),
              const Divider(),
              const _SectionHeader('Security'),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Auto-lock'),
                subtitle: const Text(
                    'When app lock is on, re-lock after being away'),
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
