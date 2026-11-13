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
  static const version = '1.55.0';

  static const items = [
    WhatsNewItem(Icons.swap_horiz, 'Recurring transfers',
        'A loan repayment, a card bill or a monthly move to savings can now repeat: choose Transfer as the type and pick the two accounts.'),
    WhatsNewItem(Icons.event_repeat, 'More schedules, and skip one',
        'Rules can repeat every 2 weeks, 3 months or 6 months. Open a rule to skip its next occurrence.'),
    WhatsNewItem(Icons.edit_note, 'Bills that differ each time',
        'Switch on "Ask me each time" and the rule waits for you to confirm the amount instead of posting a fixed one.'),
    WhatsNewItem(Icons.cloud_done_outlined, 'Backups and reminders keep up',
        'Changes are backed up as you leave the app, and bill reminders are set for the next six due dates, not only the next one.'),
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
