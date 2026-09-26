import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/backup_service.dart';
import '../utils/app_colors.dart';
import '../utils/build_info.dart';
import '../utils/insets.dart';
import '../widgets/section_header.dart';
import 'accounts_screen.dart';
import 'backups_screen.dart';
import 'budgets_screen.dart';
import 'cashflow_screen.dart';
import 'category_trends_screen.dart';
import 'goals_screen.dart';
import 'investments_screen.dart';
import 'monthly_summary_screen.dart';
import 'recurring_screen.dart';
import 'settings_screen.dart';
import 'sms_review_screen.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  DateTime? _lastBackup;

  @override
  void initState() {
    super.initState();
    _loadLastBackup();
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

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (context) => screen));

  @override
  Widget build(BuildContext context) {
    final stale = _lastBackup == null ||
        DateTime.now().difference(_lastBackup!) > const Duration(days: 7);
    final warn = warningColor(context);
    return Scaffold(
      body: ListView(
        // Leaves room under the dashboard FAB so the last tile stays tappable.
        padding: scrollPadding(context, all: 12, fab: true),
        children: [
          // Grouped into carded sections so a growing list of destinations
          // stays scannable instead of reading as one long plain column, and
          // each entry wears a tinted icon badge so it is found by colour as
          // well as by name.
          const SectionHeader('Insights',
              padding: EdgeInsets.fromLTRB(4, 4, 4, 8)),
          _MenuCard(children: [
            _MenuTile(
              icon: Icons.summarize,
              color: _MenuColors.blue,
              title: 'Monthly Summary',
              onTap: () => _open(const MonthlySummaryScreen()),
            ),
            _MenuTile(
              icon: Icons.stacked_bar_chart,
              color: _MenuColors.teal,
              title: 'Cash Flow',
              onTap: () => _open(const CashflowScreen()),
            ),
            _MenuTile(
              icon: Icons.show_chart,
              color: _MenuColors.violet,
              title: 'Category Trends',
              onTap: () => _open(const CategoryTrendsScreen()),
            ),
          ]),
          const SectionHeader('Manage',
              padding: EdgeInsets.fromLTRB(4, 16, 4, 8)),
          _MenuCard(children: [
            _MenuTile(
              icon: Icons.account_balance,
              color: _MenuColors.indigo,
              title: 'Accounts',
              onTap: () => _open(const AccountsScreen()),
            ),
            _MenuTile(
              icon: Icons.account_balance_wallet,
              color: _MenuColors.orange,
              title: 'Budgets',
              onTap: () => _open(const BudgetsScreen()),
            ),
            _MenuTile(
              icon: Icons.flag_outlined,
              color: _MenuColors.green,
              title: 'Savings Goals',
              subtitle: 'Save toward a target by a date',
              onTap: () => _open(const GoalsScreen()),
            ),
            _MenuTile(
              icon: Icons.repeat,
              color: _MenuColors.pink,
              title: 'Recurring',
              onTap: () => _open(const RecurringScreen()),
            ),
            _MenuTile(
              icon: Icons.trending_up,
              color: _MenuColors.teal,
              title: 'Investments',
              onTap: () => _open(const InvestmentsScreen()),
            ),
          ]),
          const SectionHeader('Data',
              padding: EdgeInsets.fromLTRB(4, 16, 4, 8)),
          _MenuCard(children: [
            // Hidden until SMS reading is switched on in Settings, so the
            // entry never leads to a screen that can only report it is off.
            if (context.watch<SettingsProvider>().smsImportEnabled)
              _MenuTile(
                icon: Icons.sms,
                color: _MenuColors.blue,
                title: 'Import from SMS',
                subtitle: 'Find transactions in bank alerts',
                onTap: () => _open(const SmsReviewScreen()),
              ),
            _MenuTile(
              icon: Icons.cloud,
              color: stale ? warn : _MenuColors.indigo,
              title: 'Backup & Export',
              subtitle: _backupSubtitle,
              subtitleColor: stale ? warn : null,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const BackupsScreen()),
                );
                _loadLastBackup();
              },
            ),
          ]),
          const SectionHeader('App', padding: EdgeInsets.fromLTRB(4, 16, 4, 8)),
          _MenuCard(children: [
            _MenuTile(
              icon: Icons.settings,
              color: _MenuColors.slate,
              title: 'Settings',
              onTap: () => _open(const SettingsScreen()),
            ),
            SwitchListTile(
              secondary: const _IconBadge(
                  icon: Icons.fingerprint, color: _MenuColors.violet),
              title: const Text('App lock'),
              subtitle:
                  const Text('Require biometrics or device PIN on launch'),
              value: context.watch<SettingsProvider>().appLockEnabled,
              onChanged: context.read<SettingsProvider>().setAppLockEnabled,
            ),
          ]),
          // Visible without digging into Settings > About, so "which build am
          // I running" is answerable at a glance.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Finance Tracker ${BuildInfo.label}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: mutedTextColor(context)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge colours for the menu. Mid-tone shades that hold contrast as an icon
/// on their own 15% tint in light mode and on a 28% tint in dark mode.
class _MenuColors {
  static const blue = Color(0xFF1E88E5);
  static const teal = Color(0xFF00897B);
  static const violet = Color(0xFF7E57C2);
  static const indigo = Color(0xFF3949AB);
  static const orange = Color(0xFFEF6C00);
  static const green = Color(0xFF43A047);
  static const pink = Color(0xFFD81B60);
  static const slate = Color(0xFF546E7A);
}

/// A rounded-square icon on a tint of its own colour.
class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? Color.lerp(color, Colors.white, 0.35)! : color;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.28 : 0.14),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 21, color: fg),
    );
  }
}

/// One card holding a section's tiles, separated by inset dividers.
class _MenuCard extends StatelessWidget {
  final List<Widget> children;
  const _MenuCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 70),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      // The card supplies the rounding; square tiles keep the ink flush.
      shape: const RoundedRectangleBorder(),
      leading: _IconBadge(icon: icon, color: color),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!,
              style: subtitleColor == null
                  ? null
                  : TextStyle(color: subtitleColor)),
      trailing: Icon(Icons.chevron_right, color: mutedTextColor(context)),
      onTap: onTap,
    );
  }
}
