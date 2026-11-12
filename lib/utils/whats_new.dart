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
  static const version = '1.53.0';

  static const items = [
    WhatsNewItem(Icons.sms_outlined, 'SMS import reads more banks',
        'SBI, Axis, ICICI, Bank of Baroda, Union and Amex alerts that were skipped, misread or left unnamed are picked up properly.'),
    WhatsNewItem(Icons.swap_vert, 'Fewer wrong guesses',
        'A purchase worded "credited to the shop" is no longer income, and a credit limit increase is no longer money received.'),
    WhatsNewItem(Icons.checklist, 'A tidier review screen',
        'One row to select, dismiss or set the account for the ticked messages, and the reason a row needs attention is shown in full.'),
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
