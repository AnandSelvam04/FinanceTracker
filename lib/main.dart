import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/providers/budget_provider.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/providers/goal_provider.dart';
import 'package:finance_tracker/providers/investment_provider.dart';
import 'package:finance_tracker/providers/recurring_provider.dart';
import 'package:finance_tracker/providers/settings_provider.dart';
import 'package:finance_tracker/providers/template_provider.dart';
import 'package:finance_tracker/screens/home_screen.dart';
import 'package:finance_tracker/screens/onboarding_screen.dart';
import 'package:finance_tracker/services/auth_service.dart';
import 'package:finance_tracker/services/notification_service.dart';
import 'package:finance_tracker/utils/app_theme.dart';
import 'package:finance_tracker/utils/build_info.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final seenOnboarding = prefs.getBool('seenOnboarding') ?? false;
  final biometricEnabled = prefs.getBool('biometricEnabled') ?? false;
  final settings = SettingsProvider();
  await settings.load();
  // Before the first frame, so the About tile never shows a placeholder.
  await BuildInfo.load();
  await NotificationService.instance.init();
  runApp(FinanceTrackerApp(
    settings: settings,
    seenOnboarding: seenOnboarding,
    requireAuth: seenOnboarding && biometricEnabled,
  ));
}

class FinanceTrackerApp extends StatelessWidget {
  final SettingsProvider settings;
  final bool seenOnboarding;
  final bool requireAuth;
  const FinanceTrackerApp({
    super.key,
    required this.settings,
    required this.seenOnboarding,
    this.requireAuth = false,
  });

  @override
  Widget build(BuildContext context) {
    final Widget home =
        seenOnboarding ? const HomeScreen() : const OnboardingWrapper();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => InvestmentProvider()),
        ChangeNotifierProvider(create: (_) => BudgetProvider()),
        ChangeNotifierProvider(create: (_) => AccountProvider()),
        // Transaction amounts are stored in their source account's currency,
        // so ExpenseProvider needs the accounts' exchange rates to report
        // base-currency totals. Proxied rather than pushed by hand at each
        // call site, so the two can't drift apart.
        ChangeNotifierProxyProvider<AccountProvider, ExpenseProvider>(
          create: (_) => ExpenseProvider(),
          update: (_, accounts, expenses) => (expenses ?? ExpenseProvider())
            ..syncAccountRates(accounts.ratesByAccount),
        ),
        ChangeNotifierProvider(create: (_) => RecurringProvider()),
        ChangeNotifierProvider(create: (_) => TemplateProvider()),
        ChangeNotifierProvider(create: (_) => GoalProvider()),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) => MaterialApp(
          title: 'Finance Tracker',
          // Material 3 with the same green seed in both modes, so dark mode
          // keeps the brand color instead of falling back to grey. Component
          // theming (cards, nav bar, inputs, transitions) lives in AppTheme.
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: settings.themeMode,
          home: requireAuth
              ? AuthGate(lockAfter: settings.lockTimeout, child: home)
              : home,
        ),
      ),
    );
  }
}

/// Shows a lock screen until the user authenticates, instead of
/// silently refusing to launch when authentication fails.
class AuthGate extends StatefulWidget {
  final Widget child;
  final Duration lockAfter;
  const AuthGate({
    super.key,
    required this.child,
    this.lockAfter = AuthService.lockAfter,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  bool _unlocked = false;
  bool _checking = true;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tryUnlock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-lock if the app was in the background longer than the grace period.
      if (_unlocked &&
          AuthService.shouldRelock(
            backgroundedAt: _backgroundedAt,
            now: DateTime.now(),
            lockAfter: widget.lockAfter,
          )) {
        setState(() => _unlocked = false);
        _tryUnlock();
      }
      _backgroundedAt = null;
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Only start the clock while unlocked; if already locked, keep it locked.
      _backgroundedAt ??= DateTime.now();
    }
  }

  Future<void> _tryUnlock() async {
    setState(() => _checking = true);
    // If the device can't authenticate at all, don't lock the user out.
    if (!await _authService.canAuthenticate()) {
      if (mounted) setState(() => _unlocked = true);
      return;
    }
    final ok = await _authService.authenticate();
    if (!mounted) return;
    setState(() {
      _unlocked = ok;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: Colors.green),
            const SizedBox(height: 16),
            Text('Finance Tracker is locked',
                style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 24),
            if (_checking)
              const CircularProgressIndicator()
            else
              ElevatedButton.icon(
                icon: const Icon(Icons.fingerprint),
                label: const Text('Unlock'),
                onPressed: _tryUnlock,
              ),
          ],
        ),
      ),
    );
  }
}

class OnboardingWrapper extends StatefulWidget {
  const OnboardingWrapper({super.key});
  @override
  State<OnboardingWrapper> createState() => _OnboardingWrapperState();
}

class _OnboardingWrapperState extends State<OnboardingWrapper> {
  @override
  Widget build(BuildContext context) {
    return OnboardingScreen(
      onFinish: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('seenOnboarding', true);
        if (!mounted) return;
        // ignore: use_build_context_synchronously
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      },
    );
  }
}
