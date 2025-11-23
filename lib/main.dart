import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import 'package:finance_tracker/services/app_service.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/providers/investment_provider.dart';

import 'package:finance_tracker/screens/home_screen.dart';
import 'package:finance_tracker/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final seenOnboarding = prefs.getBool('seenOnboarding') ?? false;
  final biometricEnabled = prefs.getBool('biometricEnabled') ?? false;
  if (seenOnboarding && biometricEnabled) {
    final auth = LocalAuthentication();
    final canAuthenticate =
        await auth.canCheckBiometrics || await auth.isDeviceSupported();
    if (canAuthenticate) {
      final authenticated = await auth.authenticate(
        localizedReason: 'Authenticate to access Finance Tracker',
      );
      if (!authenticated) {
        // Exit app if not authenticated
        return;
      }
    }
  }
  runApp(FinanceTrackerApp(seenOnboarding: seenOnboarding));
}

class FinanceTrackerApp extends StatelessWidget {
  final bool seenOnboarding;
  const FinanceTrackerApp({super.key, required this.seenOnboarding});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
        ChangeNotifierProvider(create: (_) => InvestmentProvider()),
      ],
      child: MaterialApp(
        title: 'Finance Tracker',
        theme: ThemeData(
          primarySwatch: Colors.green,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.system,
        home: seenOnboarding ? const HomeScreen() : const OnboardingWrapper(),
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
