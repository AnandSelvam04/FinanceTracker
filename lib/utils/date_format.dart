// Date formatting helpers.

const List<String> _weekdayAbbr = [
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
];

const List<String> _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// ISO-style date, e.g. "2026-07-24".
String formatIsoDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Date prefixed with its weekday, e.g. "Fri, 2026-07-24".
/// DateTime.weekday is 1 (Mon) .. 7 (Sun).
String formatDateWithDay(DateTime date) =>
    '${_weekdayAbbr[(date.weekday - 1) % 7]}, ${formatIsoDate(date)}';

/// Full month name; [month] is 1 (January) .. 12 (December).
String monthName(int month) => _monthNames[(month - 1) % 12];
