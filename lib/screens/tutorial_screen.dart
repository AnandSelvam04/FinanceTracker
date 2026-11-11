import 'package:flutter/material.dart';

import '../utils/insets.dart';
import '../widgets/fade_slide_in.dart';

class TutorialScreen extends StatelessWidget {
  const TutorialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const steps = <_TutorialStep>[
      _TutorialStep(
        title: 'Add a transaction',
        body: 'Tap + on any tab for an expense or income, a transfer between '
            'your accounts, or an investment. Save one you repeat as a '
            'quick-add and it becomes a one-tap chip on Home.',
        icon: Icons.playlist_add,
      ),
      _TutorialStep(
        title: 'Scan a receipt or speak',
        body: 'From +, Scan receipt reads the amount, date and shop from a '
            'photo; Add by voice takes "Spent 250 on lunch". Both only fill '
            'in the form — you review before saving.',
        icon: Icons.document_scanner_outlined,
      ),
      _TutorialStep(
        title: 'Import from bank SMS',
        body: 'Turn on Read SMS for transactions in More → Settings, then '
            'open Import SMS on Home. Give each account its last 4 digits '
            'so alerts land on the right one. Nothing is recorded until you '
            'confirm it.',
        icon: Icons.sms_outlined,
      ),
      _TutorialStep(
        title: 'Accounts and credit cards',
        body: 'More → Accounts holds your cash, bank and card balances; tap '
            'one for its statement. Cards on Home shows what each card owes, '
            'its bill and due date. Pay a card bill as a Transfer from your '
            'bank to the card.',
        icon: Icons.credit_card,
      ),
      _TutorialStep(
        title: 'Budgets',
        body: 'The Budgets tab caps a category, or all spending, for a '
            'month and shows whether today\'s pace will keep you under it.',
        icon: Icons.account_balance_wallet,
      ),
      _TutorialStep(
        title: 'Find and fix transactions',
        body: 'On Transactions, search, filter or pick All years. Tap a row '
            'to edit, split or duplicate it; long-press to select several '
            'and move or delete them together.',
        icon: Icons.search,
      ),
      _TutorialStep(
        title: 'Categories',
        body: 'More → Categories adds your own categories with an icon and '
            'colour, and renames, merges or removes existing ones.',
        icon: Icons.category_outlined,
      ),
      _TutorialStep(
        title: 'See where the money went',
        body: 'Home switches between Month and Year. More → Insights has '
            'the monthly summary (with a PDF statement), cash flow, '
            'category trends and a spending calendar.',
        icon: Icons.bar_chart,
      ),
      _TutorialStep(
        title: 'Back up',
        body: 'Your data lives only on this phone. More → Backup & Export '
            'saves it to Google Drive (automatically, once a day, if you '
            'switch that on) or to a file, and restores it on a new phone.',
        icon: Icons.cloud_upload,
      ),
      _TutorialStep(
        title: 'Privacy',
        body: 'The eye button on Home hides every amount. App lock in the '
            'More tab asks for your fingerprint or PIN to open the app.',
        icon: Icons.fingerprint,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('How to use')),
      body: ListView.separated(
        padding: scrollPadding(context),
        itemBuilder: (context, index) {
          final step = steps[index];
          final scheme = Theme.of(context).colorScheme;
          return FadeSlideIn(
            delay: Duration(milliseconds: 60 * index),
            child: Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.secondaryContainer,
                  child: Icon(step.icon, color: scheme.onSecondaryContainer),
                ),
                title: Text(step.title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(step.body),
              ),
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
