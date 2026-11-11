import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'build_info.dart';

/// One line of the "What's new" sheet.
class WhatsNewItem {
  final IconData icon;
  final String title;
  final String body;
  const WhatsNewItem(this.icon, this.title, this.body);
}

/// What changed in the release on this phone, shown once after an update.
///
/// The app is sideloaded and updated often; without this a new feature was
/// only found by stumbling on it. Update [version] and [items] together with
/// `version:` in pubspec.yaml when a release has something worth telling.
class WhatsNew {
  WhatsNew._();

  /// The release [items] describe, without the build number.
  static const version = '1.52.0';

  static const items = [
    WhatsNewItem(Icons.calculate_outlined, 'Sums in the amount field',
        'Type 250+80 or 1200/3 — the + − × ÷ keys sit under the amount.'),
    WhatsNewItem(Icons.dashboard_customize_outlined, 'Your own home screen',
        'Reorder or hide its sections and choose the shortcuts: More → Customise home.'),
    WhatsNewItem(Icons.lightbulb_outline, 'Insights on Home',
        'What changed this month in plain words, a budget ring and your no-spend streak.'),
    WhatsNewItem(Icons.search, 'Find anything',
        'Search every screen and setting from the top of More. Cards are listed there now too.'),
    WhatsNewItem(Icons.swipe_outlined, 'Swipe to edit or delete',
        'On budgets, recurring rules, goals and accounts, as on transactions.'),
    WhatsNewItem(Icons.dark_mode_outlined, 'True black and wallpaper colours',
        'A pure-black dark theme and an accent taken from your wallpaper, in Settings.'),
    WhatsNewItem(Icons.app_shortcut_outlined, 'Shortcuts on the app icon',
        'Long-press the icon to add an expense, scan a receipt or speak one.'),
    WhatsNewItem(Icons.tablet_android_outlined, 'Tablets and landscape',
        'A side rail and a two-column home screen on wide displays.'),
  ];

  static const _kSeen = 'whatsNewSeenVersion';

  /// Whether the running build is the one [items] describe. A build that
  /// does not know its version (tests, `flutter run` without a package)
  /// never is.
  static bool describesThisBuild([String? running]) {
    final v = running ?? BuildInfo.version;
    return v == version || v.startsWith('$version+');
  }

  /// Whether to show the sheet now: this build has news the user has not
  /// been shown.
  static Future<bool> shouldShow({String? running}) async {
    if (!describesThisBuild(running)) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSeen) != version;
  }

  /// Records that this release's news was shown (or, on a fresh install,
  /// that there is nothing "new" to someone who has only just arrived).
  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSeen, version);
  }
}
