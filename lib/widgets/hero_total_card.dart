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

  /// An icon shown in a disc at the card's top-right corner: what the total
  /// is the total *of* (the account's kind, say).
  final IconData? badge;

  /// With [badge], makes the disc a shared element: the row avatar that
  /// carries the same tag on the previous screen flies into it as this
  /// screen opens, so the detail visibly grows out of the row that was
  /// tapped.
  final Object? heroTag;

  const HeroTotalCard({
    super.key,
    required this.label,
    required this.amount,
    this.caption,
    this.footer,
    this.badge,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final fg = onBrandGradient(context);
    final subtle = fg.withValues(alpha: 0.82);
    Widget? disc;
    if (badge != null) {
      disc = Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Icon(badge, color: fg, size: 22),
      );
      if (heroTag != null) disc = Hero(tag: heroTag!, child: disc);
    }
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                    color: subtle,
                  ),
                ),
              ),
              if (disc != null) ...[const SizedBox(width: 12), disc],
            ],
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
