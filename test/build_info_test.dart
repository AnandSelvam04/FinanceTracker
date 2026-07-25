import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/utils/build_info.dart';

void main() {
  group('BuildInfo', () {
    test('label combines version and commit', () {
      expect(BuildInfo.label, '${BuildInfo.version} (${BuildInfo.commit})');
    });

    test('falls back to placeholders when not injected', () {
      // `flutter test` passes no --dart-define, so these are the defaults.
      // CI overrides both when building the APK.
      expect(BuildInfo.version, 'dev');
      expect(BuildInfo.commit, 'local');
      expect(BuildInfo.label, 'dev (local)');
    });
  });
}
