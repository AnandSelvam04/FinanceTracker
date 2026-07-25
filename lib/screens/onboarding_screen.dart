import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onFinish;
  const OnboardingScreen({super.key, this.onFinish});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _page = 0;

  /// Built per-build so the copy follows the active locale.
  List<_OnboardPage> _buildPages(AppLocalizations l) => [
        _OnboardPage(
          title: l.onbTitle1,
          description: l.onbBody1,
          icon: Icons.account_balance_wallet,
        ),
        _OnboardPage(
          title: l.onbTitle2,
          description: l.onbBody2,
          icon: Icons.security,
        ),
        _OnboardPage(
          title: l.onbTitle3,
          description: l.onbBody3,
          icon: Icons.pie_chart,
        ),
      ];

  static const int _pageCount = 3;

  void _next() {
    if (_page < _pageCount - 1) {
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
    final l = AppLocalizations.of(context);
    final page = _buildPages(l)[_page];
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
                child:
                    Text(_page < _pageCount - 1 ? l.next : l.getStarted),
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
