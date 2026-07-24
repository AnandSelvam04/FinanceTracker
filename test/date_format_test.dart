import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/utils/date_format.dart';

void main() {
  group('date_format', () {
    test('formatIsoDate zero-pads month and day', () {
      expect(formatIsoDate(DateTime(2026, 7, 4)), '2026-07-04');
      expect(formatIsoDate(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('formatDateWithDay prefixes the weekday', () {
      // 2026-07-24 is a Friday; 2026-07-19 is a Sunday.
      expect(formatDateWithDay(DateTime(2026, 7, 24)), 'Fri, 2026-07-24');
      expect(formatDateWithDay(DateTime(2026, 7, 19)), 'Sun, 2026-07-19');
      // Monday boundary (weekday == 1).
      expect(formatDateWithDay(DateTime(2026, 7, 20)), 'Mon, 2026-07-20');
    });
  });
}
