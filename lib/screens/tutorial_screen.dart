import 'package:flutter/material.dart';

class TutorialScreen extends StatelessWidget {
  const TutorialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final steps = <_TutorialStep>[
      const _TutorialStep(
        title: 'Add your first entries',
        body:
            'Use Add Expense or Add Investment to record transactions with amount, date, and category/type.',
        icon: Icons.playlist_add,
      ),
      const _TutorialStep(
        title: 'See monthly or yearly totals',
        body:
            'On Home, switch Month/Year to view charts, totals, and category breakdowns.',
        icon: Icons.bar_chart,
      ),
      const _TutorialStep(
        title: 'Back up before switching devices',
        body:
            'Open Backups to save to Google Drive (appData) or create a local JSON/CSV export.',
        icon: Icons.cloud_upload,
      ),
      const _TutorialStep(
        title: 'Restore anytime',
        body:
            'Use Restore from Drive or local JSON to bring data back after reinstall or on a new phone.',
        icon: Icons.restore,
      ),
      const _TutorialStep(
        title: 'Set budgets and track spending',
        body:
            'Add monthly budgets per category in the Budgets tab to monitor progress and avoid overspending.',
        icon: Icons.account_balance_wallet,
      ),
      const _TutorialStep(
        title: 'Optional app lock',
        body:
            'Enable "App lock" in the More tab to require biometrics or your device PIN on launch.',
        icon: Icons.fingerprint,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('How to use')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          final step = steps[index];
          return Card(
            child: ListTile(
              leading: Icon(step.icon),
              title: Text(step.title),
              subtitle: Text(step.body),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemCount: steps.length,
      ),
    );
  }
}

class _TutorialStep {
  final String title;
  final String body;
  final IconData icon;
  const _TutorialStep({
    required this.title,
    required this.body,
    required this.icon,
  });
}
