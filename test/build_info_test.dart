import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/utils/build_info.dart';

void main() {
  group('BuildInfo', () {
    test('a build with no commit shows just the version', () {
      // `flutter test` passes no --dart-define, so commit is the placeholder.
      // This is also the shape of a locally built, sideloaded APK.
      expect(BuildInfo.hasCommit, isFalse);
      expect(BuildInfo.commit, BuildInfo.unknownCommit);
      expect(BuildInfo.label, BuildInfo.version);
      // A bare "(local)" told the user nothing, so it is no longer appended.
      expect(BuildInfo.label, isNot(contains('(')));
    });

    test('version falls back only when nothing else is known', () async {
      // No define, and PackageInfo has no platform binding under the test
      // harness, so load() fails softly and the placeholder stands.
      await BuildInfo.load();
      expect(BuildInfo.version, 'dev');
    });

    test('load() does not throw when the platform cannot answer', () {
      // Launch must not depend on the version being readable.
      expect(BuildInfo.load(), completes);
    });
  });
}
