import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finance_tracker/utils/whats_new.dart';

void main() {
  test('describes the version in pubspec.yaml', () {
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync())!
        .group(1)!;
    expect(WhatsNew.describesThisBuild(version), isTrue,
        reason: 'WhatsNew.version (${WhatsNew.version}) is out of step with '
            'pubspec.yaml ($version); update both together');
  });

  test('a build that does not know its version shows nothing', () async {
    SharedPreferences.setMockInitialValues({});
    expect(WhatsNew.describesThisBuild('dev'), isFalse);
    expect(await WhatsNew.shouldShow(running: 'dev'), isFalse);
    // A later release is not this one either.
    expect(WhatsNew.describesThisBuild('${WhatsNew.version}1+9'), isFalse);
  });

  test('shows once per release', () async {
    SharedPreferences.setMockInitialValues({});
    final running = '${WhatsNew.version}+83';
    expect(await WhatsNew.shouldShow(running: running), isTrue);
    await WhatsNew.markSeen();
    expect(await WhatsNew.shouldShow(running: running), isFalse);
  });

  test('shows again after an update from an older release', () async {
    SharedPreferences.setMockInitialValues({'whatsNewSeenVersion': '1.40.0'});
    expect(await WhatsNew.shouldShow(running: WhatsNew.version), isTrue);
  });
}
