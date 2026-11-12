import 'package:flutter/material.dart';
import '../utils/dimens.dart';

/// The red strip revealed behind a row while it is swiped away to delete.
///
/// The rows are rounded cards, and a bare full-bleed Container behind them
/// showed square red corners poking out around the card as it slid. This
/// matches the card's corner radius and labels the action, so the swipe reads
/// as "delete" before the confirm dialog appears.
class SwipeDeleteBackground extends StatelessWidget {
  const SwipeDeleteBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      decoration: BoxDecoration(
        color: scheme.error,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Delete',
              style: TextStyle(
                  color: scheme.onError, fontWeight: FontWeight.w600)),
          const SizedBox(width: Space.sm),
          Icon(Icons.delete_outline, color: scheme.onError),
        ],
      ),
    );
  }
}
