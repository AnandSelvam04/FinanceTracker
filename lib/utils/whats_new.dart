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
    WhatsNewItem(Icons.credit_score_outlined, 'Card EMIs post once',
        'An EMI instalment could be added twice when the app was opened and resumed at the same moment. It is now added once.'),
    WhatsNewItem(Icons.savings_outlined, 'Investments always have a name',
        'Leave the name blank and it is saved as the type and month, like "PPF Nov 2026". Entries saved blank before now show that way too.'),
    WhatsNewItem(Icons.cloud_outlined, 'Drive backup, updated',
        'Drive backup uses Google\'s current permission prompt. Switch account now asks again for Drive access on the next backup.'),
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
