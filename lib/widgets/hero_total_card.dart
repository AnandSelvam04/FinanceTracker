import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

/// A brand-gradient card that leads a screen with its headline total: a small
/// uppercase label, the amount in large type, an optional caption, and an
/// optional [footer] (e.g. an allocation bar).
///
/// The same treatment as the dashboard's net-worth card and the goals summary,
/// so every "how much in total" figure in the app reads alike instead of some
/// screens using a flat tinted row with body-sized text.
class HeroTotalCard extends StatelessWidget {
  final String label;
  final String amount;
  final String? caption;
  final Widget? footer;

  const HeroTotalCard({
    super.key,
    required this.label,
    required this.amount,
    this.caption,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final fg = onBrandGradient(context);
    final subtle = fg.withValues(alpha: 0.82);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: brandGradient(context),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
              color: subtle,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: fg,
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!, style: TextStyle(fontSize: 13, color: subtle)),
          ],
          if (footer != null) ...[
            const SizedBox(height: 14),
            footer!,
          ],
        ],
      ),
    );
  }
}
