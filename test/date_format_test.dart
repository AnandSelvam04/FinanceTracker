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
      expect(formatDateWithDay(DateTime(2026, 7, 24)), 'Fri, 24 Jul 2026');
      expect(formatDateWithDay(DateTime(2026, 7, 19)), 'Sun, 19 Jul 2026');
      expect(formatDateWithDay(DateTime(2026, 7, 20)), 'Mon, 20 Jul 2026');
    });
  });

  group('formatShortDate / formatMonthYear', () {
    test('read as day, short month, year', () {
      expect(formatShortDate(DateTime(2026, 9, 5)), '5 Sep 2026');
      expect(formatMonthYear(2026, 12), 'December 2026');
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
