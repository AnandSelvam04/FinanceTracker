import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/insets.dart';

class TutorialScreen extends StatelessWidget {
  const TutorialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final steps = <_TutorialStep>[
      _TutorialStep(
        title: l.tutStep1Title,
        body: l.tutStep1Body,
        icon: Icons.playlist_add,
      ),
      _TutorialStep(
        title: l.tutStep2Title,
        body: l.tutStep2Body,
        icon: Icons.bar_chart,
      ),
      _TutorialStep(
        title: l.tutStep3Title,
        body: l.tutStep3Body,
        icon: Icons.cloud_upload,
      ),
      _TutorialStep(
        title: l.tutStep4Title,
        body: l.tutStep4Body,
        icon: Icons.restore,
      ),
      _TutorialStep(
        title: l.tutStep5Title,
        body: l.tutStep5Body,
        icon: Icons.account_balance_wallet,
      ),
      _TutorialStep(
        title: l.tutStep6Title,
        body: l.tutStep6Body,
        icon: Icons.fingerprint,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l.howToUse)),
      body: ListView.separated(
        padding: scrollPadding(context),
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
