import 'package:flutter/material.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onFinish;
  const OnboardingScreen({super.key, this.onFinish});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _page = 0;

  static const List<_OnboardPage> _pages = [
    _OnboardPage(
      title: 'Welcome to FinanceTracker',
      description:
          'Track expenses, investments, and budgets — all in one place.\n\nQuick manual entry with smart category suggestions.',
      icon: Icons.account_balance_wallet,
    ),
    _OnboardPage(
      title: 'Secure & Backup',
      description: 'PIN/biometric lock, local backup, CSV export.',
      icon: Icons.security,
    ),
    _OnboardPage(
      title: 'Dashboard & Charts',
      description: 'Visualize your spending with charts and analytics.',
      icon: Icons.pie_chart,
    ),
  ];

  void _next() {
    if (_page < _pages.length - 1) {
      setState(() => _page++);
    } else {
      if (widget.onFinish != null) {
        widget.onFinish!();
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_page];
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(page.icon, size: 80, color: Colors.green),
              const SizedBox(height: 32),
              Text(page.title,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text(page.description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _next,
                child: Text(_page < _pages.length - 1 ? 'Next' : 'Get Started'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardPage {
  final String title;
  final String description;
  final IconData icon;
  const _OnboardPage(
      {required this.title, required this.description, required this.icon});
}
