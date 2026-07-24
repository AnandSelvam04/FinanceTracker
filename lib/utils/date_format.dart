// Locale-independent date helpers. The weekday *name* is localized in
// AppLocalizations (via `dateWithDay`); the numeric part lives here so both
// locales share one canonical `YYYY-MM-DD` rendering.

/// ISO-style date, e.g. "2026-07-24".
String formatIsoDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
