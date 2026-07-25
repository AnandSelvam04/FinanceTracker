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

  group('AppLocalizations misc helpers', () {
    final en = AppLocalizations(const Locale('en'));
    final ta = AppLocalizations(const Locale('ta'));

    test('monthName maps 1..12 and is localized', () {
      expect(en.monthName(1), 'January');
      expect(en.monthName(12), 'December');
      expect(ta.monthName(7), 'ஜூலை');
    });

    test('freqLabel maps DbConstants frequency values', () {
      expect(en.freqLabel('monthly'), 'Monthly');
      expect(ta.freqLabel('monthly'), 'மாதாந்திரம்');
      // Unknown value falls through to the raw string.
      expect(en.freqLabel('fortnightly'), 'fortnightly');
    });

    test('contributions pluralizes and localizes', () {
      expect(en.contributions(1), '1 contribution');
      expect(en.contributions(3), '3 contributions');
      expect(ta.contributions(1), '1 பங்களிப்பு');
      expect(ta.contributions(3), '3 பங்களிப்புகள்');
    });

    test('totalInType substitutes the type', () {
      expect(en.totalInType('Silver'), 'Total in Silver');
      expect(ta.totalInType('Silver'), 'Silver இல் மொத்தம்');
    });

    test('paymentModeLabel maps known modes and passes through unknowns', () {
      expect(en.paymentModeLabel('Cash'), 'Cash');
      expect(ta.paymentModeLabel('Cash'), 'பணம்');
      expect(en.paymentModeLabel('UPI'), 'UPI');
      // Unknown/custom mode passes through unchanged.
      expect(ta.paymentModeLabel('Cheque'), 'Cheque');
    });

    test('daysAgo / hoursAgo pluralize', () {
      expect(en.daysAgo(1), '1 day ago');
      expect(en.daysAgo(5), '5 days ago');
      expect(en.hoursAgo(1), '1 hour ago');
      expect(en.hoursAgo(3), '3 hours ago');
    });

    test('lockAfterMinutes switches on singular/plural', () {
      expect(en.lockAfterMinutes(1), 'After 1 minute');
      expect(en.lockAfterMinutes(5), 'After 5 minutes');
      expect(en.lockAfterSeconds(15), 'After 15 seconds');
      // Tamil uses a distinct singular form and leaves no {n} unsubstituted.
      expect(ta.lockAfterMinutes(1), isNot(contains('{n}')));
      expect(ta.lockAfterMinutes(5), contains('5'));
      expect(ta.lockAfterMinutes(1), isNot(ta.lockAfterMinutes(5)));
    });

    test('onboarding and service strings are localized', () {
      expect(en.getStarted, 'Get Started');
      expect(ta.getStarted, isNot('Get Started'));
      expect(en.authReason, contains('authenticate'));
      expect(ta.channelName, isNot(en.channelName));
    });

    test('expenseBreakdownBy substitutes the category list', () {
      expect(en.expenseBreakdownBy('Food, Rent'),
          'Expense breakdown by category: Food, Rent');
    });

    test('argument substitution fills every placeholder', () {
      expect(en.importedSkipped(10, 2), 'Imported 10, skipped 2');
      expect(en.willImportSkip(8, 1), 'Will import 8, skip 1.');
      expect(en.lastBackup('just now'), 'Last backup: just now');
    });
  });
}
