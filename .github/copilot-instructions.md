# Finance Tracker: notes for coding assistants

Android-first Flutter app (Provider + SQLite via `sqflite_sqlcipher`). See
`README.md` for features and project layout.

- Money is stored as integer minor units, in the source account's currency;
  base-currency totals convert through the account's exchange rate.
- Database access goes through `lib/services/db_service.dart`; schema
  changes bump `DbConstants.dbVersion` and add a step to `_onUpgrade`.
- Text sizes come from `FontSizes`, padding and gaps from `Space`, corner
  radii from `Radii` (`lib/utils/font_sizes.dart`, `lib/utils/dimens.dart`);
  a screen reached from More or a home shortcut takes its icon and colour
  from `lib/utils/destinations.dart`. Do not type these values in.
- Before pushing: `flutter analyze` must be clean and `flutter test` must
  pass (CI runs both, then builds the arm64-v8a APK).
- Bump `version:` in `pubspec.yaml` (name and build number) with each
  user-facing change.
- Never commit signing keys or `key.properties` (`docs/SIGNING.md`).
