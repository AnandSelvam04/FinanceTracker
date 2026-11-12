import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/expense.dart';
import '../models/tx_template.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/investment_provider.dart';
import '../providers/budget_provider.dart';
import '../providers/recurring_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/template_provider.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import '../services/emi_service.dart';
import '../services/home_widget_service.dart';
import '../services/receipt_store.dart';
import '../services/recurring_service.dart';
import '../services/sms_auto_capture.dart';
import '../services/sms_service.dart';
import '../utils/alerts.dart';
import '../utils/app_colors.dart';
import '../utils/billing_cycle.dart';
import '../utils/currency_format.dart';
import '../utils/dashboard_insights.dart';
import '../utils/dashboard_layout.dart';
import '../utils/date_format.dart';
import '../utils/destinations.dart';
import '../utils/haptics.dart';
import '../utils/insets.dart';
import '../utils/merchant_summary.dart';
import '../utils/whats_new.dart';
import '../widgets/alerts_banner.dart';
import '../widgets/animated_money.dart';
import '../widgets/empty_state.dart';
import '../widgets/category_avatar.dart';
import '../widgets/category_bar_chart.dart';
import '../widgets/celebration.dart';
import '../widgets/expense_trends_chart.dart';
import '../widgets/icon_badge.dart';
import '../widgets/month_selector.dart';
import '../widgets/net_worth_card.dart';
import '../widgets/section_header.dart';
import '../widgets/skeleton.dart';
import '../widgets/top_merchants_card.dart';
import '../widgets/transaction_edit_sheet.dart';
import '../widgets/whats_new_sheet.dart';
import 'add_expense_screen.dart';
import 'add_investment_screen.dart';
import 'add_transfer_screen.dart';
import 'accounts_screen.dart';
import 'budgets_screen.dart';
import 'cashflow_screen.dart';
import 'expense_list_screen.dart';
import 'credit_cards_screen.dart';
import 'goals_screen.dart';
import 'investments_screen.dart';
import 'loans_screen.dart';
import 'monthly_summary_screen.dart';
import 'more_screen.dart';
import 'recurring_screen.dart';
import 'sms_review_screen.dart';
import 'spending_calendar_screen.dart';
import 'tutorial_screen.dart';
import '../utils/font_sizes.dart';

part 'home/dashboard.dart';
part 'home/figures.dart';
part 'home/recent.dart';
part 'home/shortcuts.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  bool _yearView = false;

  StreamSubscription<Uri?>? _widgetClicks;

  /// Providers the home-screen widget's figures come from, listened to so it
  /// stays in step (it only sends when the figures differ).
  List<ChangeNotifier> _widgetSources = const [];

  /// The home-screen widget's Add button opens the Add Expense form, and so
  /// do the app icon's long-press shortcuts — Scan receipt and Add by voice
  /// going straight to the camera and the microphone.
  void _openFromWidget(Uri? uri) {
    if (!mounted || uri == null) return;
    final AddExpenseAction action;
    if (uri.host == HomeWidgetService.addUri.host) {
      action = AddExpenseAction.none;
    } else if (uri.host == HomeWidgetService.scanUri.host) {
      action = AddExpenseAction.scan;
    } else if (uri.host == HomeWidgetService.voiceUri.host) {
      action = AddExpenseAction.voice;
    } else {
      return;
    }
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => AddExpenseScreen(autoStart: action)));
  }

  /// Once after an update, says what changed in it.
  Future<void> _showWhatsNewIfUpdated() async {
    if (!await WhatsNew.shouldShow() || !mounted) return;
    await WhatsNew.markSeen();
    if (!mounted) return;
    await showWhatsNewSheet(context);
  }

  static const _kCelebratedMonth = 'celebratedBudgetMonth';

  /// Marks a month that ended within its overall budget, once, the first
  /// time the app is opened after it.
  Future<void> _celebrateLastMonth() async {
    final expenses = context.read<ExpenseProvider>();
    final budgets = context.read<BudgetProvider>();
    final settings = context.read<SettingsProvider>();
    final now = DateTime.now();
    final last = DateTime(now.year, now.month - 1);
    final key = '${last.year}-${last.month}';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kCelebratedMonth) == key) return;
    await expenses.ensureYearsLoaded({last.year, last.year - 1});
    if (!mounted) return;
    final row = budgets.overallBudgetRow(last.year, last.month);
    if (row == null) return;
    final cap =
        budgets.capFor(row, expenses, rollover: settings.budgetRollover);
    final spent = expenses.totalForMonth(last.year, last.month);
    // Decided either way now, so an over-budget month is not looked at
    // again on every launch.
    await prefs.setString(_kCelebratedMonth, key);
    // A month with nothing recorded was not "under budget", just unused.
    if (!mounted || cap <= 0 || spent <= 0 || spent > cap) return;
    celebrate(
        context,
        'You finished ${monthName(last.month)} '
        '${formatMoneyRounded(cap - spent)} under budget!');
  }

  /// Opens what a tapped notification asked for: the SMS review queue, for
  /// a bank alert caught as it arrived.
  void _openFromNotification() {
    final requests = NotificationService.instance.openRequest;
    if (!mounted || requests.value != NotificationService.openSmsReview) {
      return;
    }
    requests.value = null;
    // Switched off since the notification was raised: nothing to show.
    if (!context.read<SettingsProvider>().smsImportEnabled) return;
    Navigator.push(context,
        MaterialPageRoute(builder: (context) => const SmsReviewScreen()));
  }

  /// Hands this month's and today's spending to the home-screen widget.
  void _syncHomeWidget() {
    if (!mounted) return;
    final expenses = context.read<ExpenseProvider>();
    final settings = context.read<SettingsProvider>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todaySpent = expenses
        .expensesInRange(today, today.add(const Duration(days: 1)))
        .where((e) => e.isExpense)
        .fold<int>(0, (t, e) => t + expenses.baseAmountOf(e));
    HomeWidgetService.push(homeWidgetData(
      now: now,
      monthSpent: expenses.totalForMonth(now.year, now.month),
      todaySpent: todaySpent,
      locked: settings.appLockEnabled,
    ));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _widgetClicks = HomeWidgetService.clicks
        .listen(_openFromWidget, onError: (Object _) {});
    HomeWidgetService.launchedFrom().then(_openFromWidget);
    NotificationService.instance.openRequest.addListener(_openFromNotification);
    // A tap that launched the app is already waiting.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _openFromNotification());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _widgetSources = [
        context.read<ExpenseProvider>(),
        context.read<SettingsProvider>(),
      ];
      for (final s in _widgetSources) {
        s.addListener(_syncHomeWidget);
      }
      _syncHomeWidget();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<ExpenseProvider>();
      // Load current year and previous year (for trends)
      provider.ensureYearLoaded(_selectedYear);
      provider.ensureYearLoaded(_selectedYear - 1);
      context.read<InvestmentProvider>().fetchInvestments();
      context.read<AccountProvider>().fetchAccounts();
      context.read<TemplateProvider>().fetchTemplates();
      // Capture providers before awaiting so we don't read context across
      // async gaps.
      final recurringProvider = context.read<RecurringProvider>();
      final budgetProvider = context.read<BudgetProvider>();
      await recurringProvider.fetchRules();
      // Budgets power both the in-app alerts banner and budget notifications.
      await budgetProvider.fetchBudgets();
      await budgetProvider.carryForwardIfEmpty(DateTime.now());
      await _postRecurring();
      // Receipt photos whose transactions are gone. Once per launch only, and
      // not from _postRecurring (which also runs on every resume and rule
      // change): a deleted transaction keeps its photo for as long as its
      // Undo can still bring it back. Not awaited, so it never blocks the
      // dashboard.
      unawaited(ReceiptStore.prune().catchError((Object _) => 0));
      // Safety net: keep a fresh local backup even if the user never
      // taps "Backup" (data otherwise lives only on this device).
      await BackupService().autoBackupIfDue();
      if (!mounted) return;
      await _syncNotifications();
      if (!mounted) return;
      // The on-device backup above is lost with the phone; this copy isn't.
      // Opt-in, silent (no sign-in prompt), and not awaited: it waits on the
      // network, which must not hold up the rest of the launch.
      unawaited(BackupService().autoDriveBackupIfDue());
      await _celebrateLastMonth();
      if (!mounted) return;
      unawaited(_showWhatsNewIfUpdated());
      // From here on keep reminders in step with the data, not just the
      // launch-time snapshot: a deleted or edited rule used to keep its old
      // "Bill due soon" reminder, and switching notifications back on
      // scheduled nothing until the next cold start.
      _recurring = recurringProvider..addListener(_onRulesChanged);
      _settings = context.read<SettingsProvider>()
        ..addListener(_onSettingsChanged);
      _notificationsWereOn = _settings!.notificationsEnabled;
      _reminderWas = _settings!.dailyReminderMinutes;
      // Paying a card bill, adding a spend or a SIP contribution changes
      // what the card and budget reminders should say. They used to be
      // worked out only at launch, so a paid card still got its "payment
      // due" notification while the app stayed open in the background.
      _dataSources = [
        context.read<ExpenseProvider>(),
        context.read<InvestmentProvider>(),
        context.read<BudgetProvider>(),
        context.read<AccountProvider>(),
      ];
      for (final source in _dataSources) {
        source.addListener(_scheduleResync);
      }
    });
  }

  RecurringProvider? _recurring;
  SettingsProvider? _settings;
  bool _notificationsWereOn = false;
  int? _reminderWas;
  List<ChangeNotifier> _dataSources = const [];
  Timer? _resync;

  /// Re-derives the reminders shortly after the data settles. Debounced: a
  /// load or restore notifies many times in a row.
  void _scheduleResync() {
    _resync?.cancel();
    _resync = Timer(const Duration(seconds: 2), () {
      if (mounted && (_settings?.notificationsEnabled ?? false)) {
        _syncNotifications(requestPermission: false);
      }
    });
  }

  void _onRulesChanged() {
    final settings = _settings;
    final recurring = _recurring;
    if (settings == null || recurring == null) return;
    // A rule saved already due (today, or backdated) posts now rather than
    // on the next trip to the background and back.
    _postRecurring();
    if (!settings.notificationsEnabled) return;
    NotificationService.instance.scheduleBillReminders(recurring.rules);
  }

  void _onSettingsChanged() {
    final on = _settings?.notificationsEnabled ?? false;
    final reminder = _settings?.dailyReminderMinutes;
    // Turning them off already cancels everything (Settings does that).
    if (on && !_notificationsWereOn && mounted) {
      _syncNotifications(requestPermission: false);
    } else if (on && reminder != _reminderWas && mounted) {
      // The daily reminder was switched on/off or moved to another time.
      _syncNotifications(requestPermission: false);
    }
    _notificationsWereOn = on;
    _reminderWas = reminder;
  }

  @override
  void dispose() {
    _widgetClicks?.cancel();
    NotificationService.instance.openRequest
        .removeListener(_openFromNotification);
    for (final s in _widgetSources) {
      s.removeListener(_syncHomeWidget);
    }
    WidgetsBinding.instance.removeObserver(this);
    _recurring?.removeListener(_onRulesChanged);
    _settings?.removeListener(_onSettingsChanged);
    for (final source in _dataSources) {
      source.removeListener(_scheduleResync);
    }
    _resync?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Back after a while, possibly on a new day: post what fell due and
      // bring the reminders up to date.
      _postRecurring().then((_) => _scheduleResync());
      // The SMS permission may have been granted in Android's settings while
      // the app was away; listening could not start without it.
      if (_settings?.smsAutoCapture ?? false) SmsAutoCapture.listen(on: true);
      // The wallpaper, and so its accent colour, may have changed meanwhile.
      _settings?.refreshWallpaperAccent();
    }
  }

  /// Materializes any due recurring transactions and refreshes views.
  Future<void> _postRecurring() async {
    final expenseProvider = context.read<ExpenseProvider>();
    final accountProvider = context.read<AccountProvider>();
    final investmentProvider = context.read<InvestmentProvider>();
    final recurringProvider = context.read<RecurringProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final posted = await RecurringService.instance.postDueTransactions() +
        // Card EMI instalments fall due the same way.
        await EmiService.postDue();
    if (posted > 0) {
      await expenseProvider.reloadLoadedYears();
      await accountProvider.refreshBalances();
      // SIP rules file into the investments ledger, so refresh it too —
      // otherwise newly posted contributions (and the net-worth total) stay
      // stale until a manual pull-to-refresh.
      await investmentProvider.fetchInvestments();
      await recurringProvider.fetchRules();
      if (mounted) {
        // "item" rather than "transaction": the count can include SIP
        // investment contributions, which aren't expense/income transactions.
        messenger.showSnackBar(SnackBar(
          content: Text((posted == 1
              ? '1 recurring item posted'
              : '$posted recurring items posted')),
        ));
      }
    }
  }

  /// Pull-to-refresh handler for the dashboard: re-reads everything the
  /// dashboard renders so a swipe reconciles the view with the database.
  Future<void> _refreshDashboard() async {
    final expenses = context.read<ExpenseProvider>();
    final accounts = context.read<AccountProvider>();
    final investments = context.read<InvestmentProvider>();
    final templates = context.read<TemplateProvider>();
    await Future.wait([
      expenses.reloadLoadedYears(),
      accounts.fetchAccounts(),
      investments.fetchInvestments(),
      templates.fetchTemplates(),
    ]);
    if (mounted) await accounts.refreshBalances();
  }

  /// Re-arms bill reminders and fires any new budget notifications, honoring
  /// the user's notifications setting. [requestPermission] is false when the
  /// caller has just asked (the Settings switch does).
  Future<void> _syncNotifications({bool requestPermission = true}) async {
    final settings = context.read<SettingsProvider>();
    final recurring = context.read<RecurringProvider>();
    final budgets = context.read<BudgetProvider>();
    final expenses = context.read<ExpenseProvider>();
    final accounts = context.read<AccountProvider>();
    final investments = context.read<InvestmentProvider>();
    final service = NotificationService.instance;
    if (!settings.notificationsEnabled) {
      await service.cancelAll();
      return;
    }
    if (requestPermission) await service.requestPermission();
    await service.scheduleBillReminders(recurring.rules);
    final now = DateTime.now();
    // Credit-card statement reminders. A wide window so the upcoming due date
    // is scheduled even when it is weeks out; overdueGrace 0 so a past due
    // date is never scheduled in the past.
    final cardReminders = creditCardReminders(
      accounts: accounts.accounts,
      now: now,
      // Investments bought on the card are on its statement too.
      spendInRange: (id, from, to) =>
          expenses.spendOnAccountInRange(id, from, to) +
          investments.chargedToAccountInRange(id, from, to),
      paidInRange: expenses.paidToAccountInRange,
      withinDays: 45,
      overdueGrace: 0,
    );
    await service.scheduleCreditCardReminders(cardReminders);
    // Start-up begins these loads without waiting, so make sure they are in:
    // this month's spend for the alerts, and last year's for a rollover chain
    // that reaches back past January (unloaded, December would read as
    // unspent and roll its whole cap over).
    await expenses.ensureYearsLoaded({now.year, now.year - 1});
    final alerts = budgetAlerts(
      budgets: budgets.budgets,
      year: now.year,
      month: now.month,
      spentForCategory: (c) =>
          expenses.spentForCategoryInMonth(now.year, now.month, c),
      totalSpent: () => expenses.totalForMonth(now.year, now.month),
      capFor: (b) =>
          budgets.capFor(b, expenses, rollover: settings.budgetRollover),
    );
    await service.notifyBudgetAlerts(alerts, year: now.year, month: now.month);
    await service.scheduleDailyReminder(
      settings.dailyReminderMinutes,
      loggedToday:
          expenses.expenses.any((e) => DateUtils.isSameDay(e.date, now)),
    );
  }

  Future<void> _quickAddTemplate(TxTemplate template) async {
    final expenseProvider = context.read<ExpenseProvider>();
    final accountProvider = context.read<AccountProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final expense = Expense(
      description: template.description,
      amount: template.amount,
      date: DateTime.now(),
      category: template.category,
      paymentMode: template.paymentMode ?? 'Other',
      type: template.type,
      accountId: template.accountId,
    );
    final addedId = await expenseProvider.addExpense(expense);
    await accountProvider.refreshBalances();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text('Added ${template.name}'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          await expenseProvider.deleteExpense(addedId);
          await accountProvider.refreshBalances();
        },
      ),
    ));
  }

  List<Widget> get _screens => [
        _DashboardView(
          selectedYear: _selectedYear,
          selectedMonth: _selectedMonth,
          yearView: _yearView,
          onQuickAdd: _quickAddTemplate,
          onRefresh: _refreshDashboard,
          onAddExpense: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddExpenseScreen()),
          ),
          onSeeAllTransactions: () => setState(() => _selectedIndex = 1),
          onOpenBudgets: () => setState(() => _selectedIndex = 2),
          onMonthChanged: (y, m) {
            setState(() {
              _selectedYear = y;
              _selectedMonth = m;
            });
            // Ensure the selected year is loaded — and, in January, the
            // year before it, which the insights compare against.
            final expenses = context.read<ExpenseProvider>();
            expenses.ensureYearLoaded(y);
            if (m == 1) expenses.ensureYearLoaded(y - 1);
          },
          onViewToggle: (isYear) {
            setState(() {
              _yearView = isYear;
            });
          },
        ),
        const ExpenseListScreen(),
        // A tab of its own: budgets are checked far more often than the
        // rest of the More menu, where they used to be two taps away.
        const BudgetsScreen(embedded: true),
        const MoreScreen(),
      ];

  void _showAddOptions(BuildContext context) {
    void open(Widget screen) {
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    }

    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      // SafeArea keeps the sheet's items above the system navigation bar in
      // edge-to-edge mode; without it the last tile is covered and untappable.
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child:
                    Text('Add', style: Theme.of(context).textTheme.titleLarge),
              ),
              _AddOption(
                icon: Icons.remove_circle_outline,
                color: expenseColor(context),
                title: 'Add expense',
                subtitle: 'Or income — switch at the top',
                onTap: () => open(const AddExpenseScreen()),
              ),
              _AddOption(
                icon: Icons.document_scanner_outlined,
                color: scheme.primary,
                title: 'Scan receipt',
                subtitle: 'Read the amount and date from a photo',
                onTap: () => open(
                    const AddExpenseScreen(autoStart: AddExpenseAction.scan)),
              ),
              _AddOption(
                icon: Icons.mic_none,
                color: scheme.tertiary,
                title: 'Add by voice',
                subtitle: 'Say "Spent 250 on lunch"',
                onTap: () => open(
                    const AddExpenseScreen(autoStart: AddExpenseAction.voice)),
              ),
              // Transfers (card bill payments, cash withdrawals) used to be
              // reachable only from More → Accounts.
              _AddOption(
                icon: Icons.swap_horiz,
                color: scheme.secondary,
                title: 'Transfer',
                subtitle: 'Move money between your accounts',
                onTap: () => open(const AddTransferScreen()),
              ),
              _AddOption(
                icon: Icons.trending_up,
                color: incomeColor(context),
                title: 'Add investment',
                subtitle: 'Record a contribution or withdrawal',
                onTap: () => open(const AddInvestmentScreen()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Width from which the tabs move from a bottom bar to a rail down the
  /// side: a tablet, or a phone held sideways, where a bottom bar spends the
  /// short axis and stretches five buttons across the long one.
  static const _railWidth = 720.0;

  void _selectTab(int index) {
    if (index == _selectedIndex) return;
    Haptics.tick();
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _railWidth;
    final scheme = Theme.of(context).colorScheme;
    // IndexedStack keeps every tab mounted, so the Transactions screen's
    // search, filters, and scroll position survive tab switches.
    final tabs = IndexedStack(index: _selectedIndex, children: _screens);
    return Scaffold(
      // Transactions and Budgets bring their own app bar (with their own
      // actions); showing this one above it stacked two purple bars and cost
      // a tenth of the screen.
      appBar: _selectedIndex == 1 || _selectedIndex == 2
          ? null
          : AppBar(
              title: Text(_selectedIndex == 3 ? 'More' : 'Finance Tracker'),
              actions: [
                // Masks every amount, for opening the app in front of others.
                Builder(builder: (context) {
                  final settings = context.watch<SettingsProvider>();
                  return IconButton(
                    icon: Icon(settings.hideAmounts
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    tooltip:
                        settings.hideAmounts ? 'Show amounts' : 'Hide amounts',
                    onPressed: () {
                      Haptics.light();
                      settings.setHideAmounts(!settings.hideAmounts);
                    },
                  );
                }),
                IconButton(
                  icon: const Icon(Icons.help_outline),
                  tooltip: 'How to use',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TutorialScreen()),
                    );
                  },
                ),
              ],
            ),
      body: !wide
          ? tabs
          : Row(
              children: [
                SafeArea(
                  right: false,
                  child: NavigationRail(
                    // Scrolls rather than overflowing on a phone held
                    // sideways, where the rail is taller than the screen.
                    scrollable: true,
                    labelType: NavigationRailLabelType.all,
                    backgroundColor: scheme.surface,
                    indicatorColor: scheme.secondaryContainer,
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: _selectTab,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: FloatingActionButton(
                        elevation: 0,
                        tooltip: 'Add transaction',
                        onPressed: () => _showAddOptions(context),
                        child: const Icon(Icons.add),
                      ),
                    ),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home),
                        label: Text('Home'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.receipt_long_outlined),
                        selectedIcon: Icon(Icons.receipt_long),
                        label: Text('Activity'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.account_balance_wallet_outlined),
                        selectedIcon: Icon(Icons.account_balance_wallet),
                        label: Text('Budgets'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.more_horiz),
                        label: Text('More'),
                      ),
                    ],
                  ),
                ),
                VerticalDivider(
                    width: 1, thickness: 1, color: scheme.outlineVariant),
                Expanded(child: tabs),
              ],
            ),
      // Add sits in the middle of the bar rather than floating over the
      // content, where it covered the amount of whichever row was behind it.
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              // Bar slots: Home, Transactions, Add, Budgets, More. Add is an
              // action, not a tab, so the tabs after it are one slot along.
              selectedIndex:
                  _selectedIndex < 2 ? _selectedIndex : _selectedIndex + 1,
              onDestinationSelected: (i) {
                if (i == 2) {
                  Haptics.light();
                  _showAddOptions(context);
                  return;
                }
                _selectTab(i < 2 ? i : i - 1);
              },
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  // Short enough to fit a fifth of a narrow phone at large text;
                  // the screen itself is titled "Transactions".
                  label: 'Activity',
                  tooltip: 'Transactions',
                ),
                NavigationDestination(
                  icon: Container(
                    width: 56,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.add,
                        color: Theme.of(context).colorScheme.onPrimary),
                  ),
                  label: 'Add',
                  tooltip: 'Add transaction',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: Icon(Icons.account_balance_wallet),
                  label: 'Budgets',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.more_horiz),
                  selectedIcon: Icon(Icons.more_horiz),
                  label: 'More',
                ),
              ],
            ),
    );
  }
}
