import 'package:flutter/material.dart';

/// A money figure that counts up (or down) to its new value instead of
/// snapping, using the app's integer minor-unit amounts.
///
/// When [value] changes, [TweenAnimationBuilder] tweens from the previously
/// rendered amount to the new one, so headline figures like net worth and the
/// monthly total animate smoothly on load and on edits.
class AnimatedMoney extends StatelessWidget {
  /// The target amount in minor units (paise/cents).
  final int value;

  /// Formats a minor-unit amount into a display string.
  final String Function(int minor) format;

  final TextStyle? style;
  final Duration duration;
  final Curve curve;

  const AnimatedMoney({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.duration = const Duration(milliseconds: 650),
    this.curve = Curves.easeOutCubic,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // begin:0 only applies on first build, so the figure counts up from zero
      // on load. On later rebuilds TweenAnimationBuilder animates from the
      // currently displayed value to the new end whenever [value] changes.
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: curve,
      builder: (context, animated, _) =>
          Text(format(animated.round()), style: style),
    );
  }
}
