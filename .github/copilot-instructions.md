# Finance Tracker: notes for coding assistants

Android-first Flutter app (Provider + SQLite via `sqflite_sqlcipher`). See
`README.md` for features and project layout.

- Money is stored as integer minor units, in the source account's currency;
  base-currency totals convert through the account's exchange rate.
- Database access goes through `lib/services/db_service.dart`; schema
  changes bump `DbConstants.dbVersion` and add a step to `_onUpgrade`.
- Before pushing: `flutter analyze` must be clean and `flutter test` must
  pass (CI runs both, then builds the arm64-v8a APK).
- Bump `version:` in `pubspec.yaml` (name and build number) with each
  user-facing change.
- Never commit signing keys or `key.properties` (`docs/SIGNING.md`).
