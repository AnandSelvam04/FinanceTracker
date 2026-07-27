import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/backup_service.dart';
import '../utils/insets.dart';
import 'accounts_screen.dart';
import 'backups_screen.dart';
import 'budgets_screen.dart';
import 'cashflow_screen.dart';
import 'category_trends_screen.dart';
import 'investments_screen.dart';
import 'monthly_summary_screen.dart';
import 'recurring_screen.dart';
import 'settings_screen.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  bool _biometricEnabled = false;
  DateTime? _lastBackup;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadLastBackup();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _biometricEnabled = prefs.getBool('biometricEnabled') ?? false;
    });
  }

  Future<void> _loadLastBackup() async {
    final t = await BackupService().lastBackupTime();
    if (mounted) setState(() => _lastBackup = t);
  }

  /// Short human-friendly backup age shown under the Backup tile, so the
  /// nudge is visible without opening the backup screen.
  String get _backupSubtitle {
    final t = _lastBackup;
    if (t == null) return 'No backup yet — tap to protect your data';
    final d = DateTime.now().difference(t);
    final ago = d.inDays >= 1
        ? (d.inDays == 1 ? '1 day ago' : '${d.inDays} days ago')
        : d.inHours >= 1
            ? (d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago')
            : 'just now';
    return 'Last backup: $ago';
  }

  Future<void> _setBiometricEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometricEnabled', value);
    if (!mounted) return;
    setState(() => _biometricEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        // Leaves room under the dashboard FAB so the last tile stays tappable.
        padding: scrollPadding(context, all: 0, fab: true),
        children: [
          ListTile(
            leading: const Icon(Icons.account_balance),
            title: const Text('Accounts'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AccountsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.summarize),
            title: const Text('Monthly Summary'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const MonthlySummaryScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.stacked_bar_chart),
            title: const Text('Cash Flow'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CashflowScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.show_chart),
            title: const Text('Category Trends'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const CategoryTrendsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.trending_up),
            title: const Text('Investments'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const InvestmentsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.repeat),
            title: const Text('Recurring'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const RecurringScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet),
            title: const Text('Budgets'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const BudgetsScreen()),
              );
            },
          ),
          Builder(builder: (context) {
            final stale = _lastBackup == null ||
                DateTime.now().difference(_lastBackup!) >
                    const Duration(days: 7);
            return ListTile(
              leading: Icon(Icons.cloud, color: stale ? Colors.orange : null),
              title: const Text('Backup & Export'),
              subtitle: Text(_backupSubtitle,
                  style: stale ? const TextStyle(color: Colors.orange) : null),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const BackupsScreen()),
                );
                _loadLastBackup();
              },
            );
          }),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('App lock'),
            subtitle: const Text('Require biometrics or device PIN on launch'),
            value: _biometricEnabled,
            onChanged: _setBiometricEnabled,
          ),
        ],
      ),
    );
  }
}
