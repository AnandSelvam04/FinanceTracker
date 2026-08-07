import 'package:flutter/material.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onFinish;
  const OnboardingScreen({super.key, this.onFinish});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    if (widget.onFinish != null) {
      widget.onFinish!();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _next() {
    if (_page < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: isLast ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: TextButton(
                  onPressed: isLast ? null : _finish,
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) => _OnboardPageView(
                  page: _pages[index],
                ),
              ),
            ),
            _PageDots(count: _pages.length, active: _page),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(isLast ? 'Get Started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardPageView extends StatelessWidget {
  final _OnboardPage page;
  const _OnboardPageView({required this.page});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(page.icon, size: 68, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 40),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            page.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated page indicator: the active dot stretches into a pill.
class _PageDots extends StatelessWidget {
  final int count;
  final int active;
  const _PageDots({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == active ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == active
                  ? scheme.primary
                  : scheme.primary.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
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
