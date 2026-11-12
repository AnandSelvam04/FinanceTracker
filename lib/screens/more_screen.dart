import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/backup_service.dart';
import '../utils/app_colors.dart';
import '../utils/build_info.dart';
import '../utils/destinations.dart';
import '../utils/insets.dart';
import '../widgets/section_header.dart';
import 'accounts_screen.dart';
import '../widgets/empty_state.dart';
import '../widgets/icon_badge.dart';
import 'backups_screen.dart';
import 'budgets_screen.dart';
import 'cashflow_screen.dart';
import 'categories_screen.dart';
import 'credit_cards_screen.dart';
import 'customize_home_screen.dart';
import 'category_trends_screen.dart';
import 'goals_screen.dart';
import 'investments_screen.dart';
import 'loans_screen.dart';
import 'tags_screen.dart';
import 'tutorial_screen.dart';
import 'monthly_summary_screen.dart';
import 'recurring_screen.dart';
import 'settings_screen.dart';
import 'sms_review_screen.dart';
import 'spending_calendar_screen.dart';

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
    // Only a copy off the phone counts: the daily on-device backup is lost
    // along with it.
    final t = await BackupService().lastOffDeviceBackupTime();
    if (mounted) setState(() => _lastBackup = t);
  }

  /// Short human-friendly backup age shown under the Backup tile, so the
  /// nudge is visible without opening the backup screen.
  String get _backupSubtitle {
    final t = _lastBackup;
    if (t == null) return 'Nothing backed up off this phone — tap to fix';
    final d = DateTime.now().difference(t);
    final ago = d.inDays >= 1
        ? (d.inDays == 1 ? '1 day ago' : '${d.inDays} days ago')
        : d.inHours >= 1
            ? (d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago')
            : 'just now';
    return 'Last backup off this phone: $ago';
  }

  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (context) => screen));

  /// Every destination, grouped the way the menu shows them. [_Entry.words]
  /// are extra things someone might type to find it.
  List<_Entry> _entries(BuildContext context, {required bool stale}) {
    final warn = warningColor(context);
    final sms = context.watch<SettingsProvider>().smsImportEnabled;
    return [
      _Entry('Insights', Destinations.reports, 'Reports',
          subtitle: 'Week, month, year or any dates · PDF and Excel',
          words: 'summary statement year in review merchants export',
          onTap: () => _open(const MonthlySummaryScreen())),
      _Entry('Insights', Destinations.cashflow, 'Cash Flow',
          words: 'income expense chart net',
          onTap: () => _open(const CashflowScreen())),
      _Entry('Insights', Destinations.trends, 'Category Trends',
          words: 'compare months chart',
          onTap: () => _open(const CategoryTrendsScreen())),
      _Entry('Insights', Destinations.calendar, 'Spending Calendar',
          words: 'daily heatmap no-spend days',
          onTap: () => _open(const SpendingCalendarScreen())),
      _Entry('Manage', Destinations.accounts, 'Accounts',
          words: 'bank cash upi wallet balance statement',
          onTap: () => _open(const AccountsScreen())),
      // Used to be reachable only from the dashboard shortcut.
      _Entry('Manage', Destinations.cards, 'Cards',
          subtitle: 'Bills, limits, EMIs and reward points',
          words: 'credit card statement due emi rewards limit',
          onTap: () => _open(const CreditCardsScreen())),
      _Entry('Manage', Destinations.categories, 'Categories',
          subtitle: 'Add your own, set icons, rename or merge',
          words: 'icon colour color',
          onTap: () => _open(const CategoriesScreen())),
      _Entry('Manage', Destinations.loans, 'Loans & lending',
          subtitle: 'Money you owe, and money owed to you',
          words: 'debt borrowed lent repay',
          onTap: () => _open(const LoansScreen())),
      _Entry('Manage', Destinations.tags, 'Tags',
          subtitle: 'Totals for #tags in your notes',
          words: 'hashtag notes',
          onTap: () => _open(const TagsScreen())),
      _Entry('Manage', Destinations.goals, 'Savings Goals',
          subtitle: 'Save toward a target by a date',
          words: 'target save',
          onTap: () => _open(const GoalsScreen())),
      _Entry('Manage', Destinations.recurring, 'Recurring',
          words: 'subscription bills rent sip repeat monthly',
          onTap: () => _open(const RecurringScreen())),
      _Entry('Manage', Destinations.investments, 'Investments',
          words: 'mutual fund stocks sip portfolio',
          onTap: () => _open(const InvestmentsScreen())),
      // Hidden until SMS reading is switched on in Settings, so the
      // entry never leads to a screen that can only report it is off.
      if (sms)
        _Entry('Data', Destinations.sms, 'Import from SMS',
            subtitle: 'Find transactions in bank alerts',
            words: 'bank alerts messages review',
            onTap: () => _open(const SmsReviewScreen())),
      _Entry(
          'Data',
          stale
              ? Destination(Destinations.backup.icon, warn)
              : Destinations.backup,
          'Backup & Export',
          subtitle: _backupSubtitle,
          subtitleColor: stale ? warn : null,
          words: 'restore drive csv excel json import download pdf',
          onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const BackupsScreen()),
        );
        _loadLastBackup();
      }),
      _Entry('App', Destinations.customiseHome, 'Customise home',
          subtitle: 'Reorder or hide sections, pick shortcuts',
          words: 'customize dashboard layout widgets arrange',
          onTap: () => _open(const CustomizeHomeScreen())),
      _Entry('App', Destinations.settings, 'Settings',
          subtitle: 'Currency, theme, alerts, app lock',
          onTap: () => _open(const SettingsScreen())),
    ];
  }

  /// Things that live on other screens but are looked for by name: the
  /// Budgets tab, the guide, and each setting. Only offered by search.
  List<_Entry> _searchOnly() {
    _Entry setting(String title, String words) =>
        _Entry('Settings', Destinations.settings, title,
            subtitle: 'In Settings',
            words: words,
            onTap: () => _open(const SettingsScreen()));
    return [
      _Entry('Screens', Destinations.budgets, 'Budgets',
          subtitle: 'Monthly caps per category',
          words: 'limit cap rollover',
          onTap: () => _open(const BudgetsScreen())),
      _Entry('Screens', Destinations.help, 'How to use',
          subtitle: 'A short guide to the app',
          words: 'help tutorial guide',
          onTap: () => _open(const TutorialScreen())),
      setting('Currency symbol', 'rupee dollar euro'),
      setting('Theme', 'dark light mode night true black amoled'),
      setting('Accent color', 'colour wallpaper material you'),
      setting('Default account', 'preselected'),
      setting('Roll over unspent budget', 'rollover carry'),
      setting('Budget & bill alerts', 'warnings banner'),
      setting('Read SMS for transactions', 'sms import bank alerts'),
      setting('Push notifications', 'reminders bills'),
      setting('Daily reminder', 'notification log'),
      setting('App lock', 'biometric fingerprint pin security auto-lock'),
      setting('Encrypt database', 'encryption security sqlcipher'),
      setting("What's new", 'version update changes about'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final stale = _lastBackup == null ||
        DateTime.now().difference(_lastBackup!) > const Duration(days: 7);
    final entries = _entries(context, stale: stale);
    final query = _query.trim().toLowerCase();
    final sections = <String>[];
    for (final e in entries) {
      if (!sections.contains(e.section)) sections.add(e.section);
    }
    final matches = query.isEmpty
        ? const <_Entry>[]
        : [...entries, ..._searchOnly()]
            .where((e) => e.matches(query))
            .toList();

    return Scaffold(
      body: ListView(
        padding: scrollPadding(context, all: 12),
        // Dragging the list puts the keyboard away, so results are not
        // hidden behind it.
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          // The menu has grown past a screenful, and settings sit a level
          // further down: finding one by name beats scanning for it.
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search screens and settings',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          if (query.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (matches.isEmpty)
              EmptyState(
                icon: Icons.search_off,
                title: 'Nothing called "${_query.trim()}"',
                message: 'Try another word, such as "backup", "theme" or '
                    '"cards".',
              )
            else
              _MenuCard(children: [for (final e in matches) e.tile()]),
          ] else ...[
            // Grouped into carded sections so a growing list of destinations
            // stays scannable instead of reading as one long plain column,
            // and each entry wears a tinted icon badge so it is found by
            // colour as well as by name.
            for (final section in sections) ...[
              SectionHeader(section,
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8)),
              _MenuCard(children: [
                for (final e in entries)
                  if (e.section == section) e.tile(),
              ]),
            ],
            // Visible without digging into Settings > About, so "which build
            // am I running" is answerable at a glance.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Finance Tracker ${BuildInfo.label}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: mutedTextColor(context)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One destination in the More menu (or its search results).
class _Entry {
  final String section;
  final Destination look;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;

  /// Extra search terms, space separated.
  final String words;
  final VoidCallback onTap;

  const _Entry(this.section, this.look, this.title,
      {this.subtitle,
      this.subtitleColor,
      this.words = '',
      required this.onTap});

  /// Whether every word of [query] (lower case) appears somewhere in the
  /// title, the subtitle or the extra terms.
  bool matches(String query) {
    final haystack = '$title ${subtitle ?? ''} $words'.toLowerCase();
    return query
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .every(haystack.contains);
  }

  Widget tile() => _MenuTile(
        icon: look.icon,
        color: look.color,
        title: title,
        subtitle: subtitle,
        subtitleColor: subtitleColor,
        onTap: onTap,
      );
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
      leading: IconBadge(icon: icon, color: color),
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
