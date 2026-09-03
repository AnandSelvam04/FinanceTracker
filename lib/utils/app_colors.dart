import 'package:flutter/material.dart';

/// Semantic transaction colors that keep enough contrast in both light and
/// dark themes. (The fixed light-theme shades used previously — e.g.
/// green.shade700 on a dark background — were hard to read in dark mode.)
bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color incomeColor(BuildContext context) =>
    _isDark(context) ? Colors.green.shade400 : Colors.green.shade700;

Color expenseColor(BuildContext context) =>
    _isDark(context) ? Colors.red.shade300 : Colors.red.shade700;

Color transferColor(BuildContext context) =>
    _isDark(context) ? Colors.blueGrey.shade200 : Colors.blueGrey.shade700;

/// Pastel avatar backgrounds for transaction rows (dark, muted equivalents
/// in dark mode).
Color incomeAvatarColor(BuildContext context) =>
    _isDark(context) ? Colors.green.shade900 : Colors.green.shade100;

Color expenseAvatarColor(BuildContext context) =>
    _isDark(context) ? Colors.red.shade900 : Colors.red.shade50;

Color transferAvatarColor(BuildContext context) =>
    _isDark(context) ? Colors.blueGrey.shade800 : Colors.blueGrey.shade100;

/// De-emphasized text color that adapts to the theme (use instead of fixed
/// grey shades).
Color mutedTextColor(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;

/// A brand gradient blended from the active color scheme, so it follows the
/// user's chosen accent (and both light/dark modes) instead of hard-coding
/// colors. Used for hero surfaces like the net-worth card, where a flat fill
/// looks plainer than the rest of a Material 3 app can.
LinearGradient brandGradient(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      scheme.primary,
      Color.lerp(scheme.primary, scheme.tertiary, 0.55) ?? scheme.primary,
    ],
  );
}

/// Foreground color that stays legible on top of [brandGradient].
Color onBrandGradient(BuildContext context) =>
    Theme.of(context).colorScheme.onPrimary;
