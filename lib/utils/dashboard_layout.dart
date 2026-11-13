/// What the dashboard is made of, and the rules for the layout the user
/// saves: its sections (reorderable, most of them hideable) and the shortcut
/// buttons. Kept as plain ids so the choice survives in preferences and in a
/// backup, and so an id a later version drops or adds never breaks a saved
/// layout.
class DashboardLayout {
  DashboardLayout._();

  static const netWorth = 'netWorth';
  static const quickAdd = 'quickAdd';
  static const figures = 'figures';
  static const insights = 'insights';
  static const shortcuts = 'shortcuts';
  static const recent = 'recent';
  static const categories = 'categories';
  static const merchants = 'merchants';
  static const trends = 'trends';

  /// Every section, in the order a new install shows them.
  static const defaultOrder = [
    netWorth,
    quickAdd,
    figures,
    insights,
    shortcuts,
    recent,
    categories,
    merchants,
    trends,
  ];

  static const sectionLabels = {
    netWorth: 'Net worth',
    quickAdd: 'Quick-add templates',
    figures: 'Spending this period',
    insights: 'Insights',
    shortcuts: 'Shortcuts',
    recent: 'Recent transactions',
    categories: 'Spending by category',
    merchants: 'Top merchants',
    trends: '12-month trend',
  };

  /// Sections that cannot be hidden: the period's figures carry the month
  /// stepper, without which nothing else on the screen can be moved.
  static const locked = {figures};

  /// Sections a new install starts with switched off, so the first home
  /// screen is short enough to take in: both are a tap away under Reports,
  /// and one switch away under More → Customise home. Someone already using
  /// the app keeps the layout they have.
  static const hiddenOnNewInstall = {merchants, trends};

  /// The chart sections, which sit in the second column on a wide screen.
  static const chartSections = {categories, merchants, trends};

  static const investments = 'investments';
  static const cards = 'cards';
  static const sms = 'sms';
  static const reports = 'reports';
  static const accounts = 'accounts';
  static const goals = 'goals';
  static const calendar = 'calendar';
  static const loans = 'loans';
  static const recurring = 'recurring';
  static const cashflow = 'cashflow';

  /// Every shortcut on offer, in the order the picker lists them.
  static const allShortcuts = [
    investments,
    cards,
    sms,
    reports,
    accounts,
    goals,
    calendar,
    loans,
    recurring,
    cashflow,
  ];

  static const shortcutLabels = {
    investments: 'Investments',
    cards: 'Cards',
    sms: 'Import SMS',
    reports: 'Reports',
    accounts: 'Accounts',
    goals: 'Goals',
    calendar: 'Calendar',
    loans: 'Loans',
    recurring: 'Recurring',
    cashflow: 'Cash flow',
  };

  static const defaultShortcuts = [investments, cards, sms];

  /// As many as fit one row of a phone without their labels being cut.
  static const maxShortcuts = 4;

  static List<String> _split(String? stored) => stored == null
      ? const []
      : [
          for (final part in stored.split(','))
            if (part.trim().isNotEmpty) part.trim(),
        ];

  /// The saved order made whole: unknown ids dropped, repeats removed, and
  /// any section the saved order does not mention (one added since) put
  /// where the default order has it, after its nearest earlier neighbour.
  static List<String> normaliseOrder(String? stored) {
    final order = <String>[];
    for (final id in _split(stored)) {
      if (defaultOrder.contains(id) && !order.contains(id)) order.add(id);
    }
    for (var i = 0; i < defaultOrder.length; i++) {
      final id = defaultOrder[i];
      if (order.contains(id)) continue;
      var at = 0;
      for (var j = i - 1; j >= 0; j--) {
        final before = order.indexOf(defaultOrder[j]);
        if (before >= 0) {
          at = before + 1;
          break;
        }
      }
      order.insert(at, id);
    }
    return order;
  }

  /// The saved hidden set, without unknown ids or sections that cannot be
  /// hidden.
  static Set<String> normaliseHidden(String? stored) => {
        for (final id in _split(stored))
          if (defaultOrder.contains(id) && !locked.contains(id)) id,
      };

  /// The saved shortcuts: known ids only, no repeats, at most
  /// [maxShortcuts]. Null (never chosen) gives the defaults; an empty choice
  /// is kept, and shows no shortcut row.
  static List<String> normaliseShortcuts(String? stored) {
    if (stored == null) return defaultShortcuts;
    final ids = <String>[];
    for (final id in _split(stored)) {
      if (allShortcuts.contains(id) && !ids.contains(id)) ids.add(id);
    }
    return ids.take(maxShortcuts).toList();
  }
}
