import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/l10n/app_localizations.dart';
import 'package:finance_tracker/utils/date_format.dart';

void main() {
  group('formatIsoDate', () {
    test('zero-pads month and day', () {
      expect(formatIsoDate(DateTime(2026, 7, 4)), '2026-07-04');
      expect(formatIsoDate(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });

  group('AppLocalizations.dateWithDay', () {
    final en = AppLocalizations(const Locale('en'));
    final ta = AppLocalizations(const Locale('ta'));

    test('English prefixes the weekday abbreviation', () {
      // 2026-07-24 is a Friday; 07-19 Sunday; 07-20 Monday (weekday == 1).
      expect(en.dateWithDay(DateTime(2026, 7, 24)), 'Fri, 2026-07-24');
      expect(en.dateWithDay(DateTime(2026, 7, 19)), 'Sun, 2026-07-19');
      expect(en.dateWithDay(DateTime(2026, 7, 20)), 'Mon, 2026-07-20');
    });

    test('Tamil localizes the weekday but keeps the ISO numerals', () {
      expect(ta.dateWithDay(DateTime(2026, 7, 24)), 'வெள், 2026-07-24');
      expect(ta.dateWithDay(DateTime(2026, 7, 19)), 'ஞாயி, 2026-07-19');
    });

    test('weekdayAbbr covers the full Mon..Sun range', () {
      expect(en.weekdayAbbr(1), 'Mon');
      expect(en.weekdayAbbr(7), 'Sun');
    });
  });
}
