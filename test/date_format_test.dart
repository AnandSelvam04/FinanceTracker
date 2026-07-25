import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/utils/date_format.dart';

void main() {
  group('formatIsoDate', () {
    test('zero-pads month and day', () {
      expect(formatIsoDate(DateTime(2026, 7, 4)), '2026-07-04');
      expect(formatIsoDate(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });

  group('formatDateWithDay', () {
    test('prefixes the weekday abbreviation', () {
      // 2026-07-24 is a Friday; 07-19 Sunday; 07-20 Monday (weekday == 1).
      expect(formatDateWithDay(DateTime(2026, 7, 24)), 'Fri, 2026-07-24');
      expect(formatDateWithDay(DateTime(2026, 7, 19)), 'Sun, 2026-07-19');
      expect(formatDateWithDay(DateTime(2026, 7, 20)), 'Mon, 2026-07-20');
    });
  });

  group('monthName', () {
    test('maps 1..12', () {
      expect(monthName(1), 'January');
      expect(monthName(7), 'July');
      expect(monthName(12), 'December');
    });
  });
}
