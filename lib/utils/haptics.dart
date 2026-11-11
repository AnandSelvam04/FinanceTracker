import 'package:flutter/services.dart';

/// The app's haptic vocabulary, so the same kind of touch feels the same on
/// every screen. Each is a no-op where the platform has no vibrator, and
/// follows the phone's own "touch feedback" setting.
class Haptics {
  Haptics._();

  /// A step or a pick: moving a month, switching a tab or a segment.
  static void tick() => HapticFeedback.selectionClick();

  /// Something was done: saved, added, toggled.
  static void light() => HapticFeedback.lightImpact();

  /// A weightier change: entering multi-select, deleting, reordering.
  static void medium() => HapticFeedback.mediumImpact();
}
