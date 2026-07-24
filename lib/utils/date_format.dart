/// Date helpers for user-facing labels. Kept separate from currency so both
/// stay small and testable.

const List<String> _weekdayAbbr = [
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
];

/// ISO-style date, e.g. "2026-07-24".
String formatIsoDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Date prefixed with its weekday so the user can see which day it was, e.g.
/// "Fri, 2026-07-24". DateTime.weekday is 1 (Mon) .. 7 (Sun).
String formatDateWithDay(DateTime date) =>
    '${_weekdayAbbr[date.weekday - 1]}, ${formatIsoDate(date)}';
