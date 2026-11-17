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
- Backups live in `lib/services/backup_service.dart`, with the payload,
  Drive access, CSV exports and errors under `lib/services/backup/`. Drive
  uses google_sign_in 7 *authorization* only; never call `authenticate()`,
  which needs a web OAuth client this app does not have.
- The keystore is reached only through `appSecureStorage`
  (`lib/services/secure_store.dart`), which holds the database key: keep
  `resetOnError: false`, and do not move to flutter_secure_storage 11 until
  a release on 10 has run on every phone (11 cannot read the v9 format).
- Pick files with `pickLocalFile` (`lib/utils/picked_file.dart`): Android can
  return a picked file without a path.
- `analysis_options.yaml` turns on `unawaited_futures` and
  `discarded_futures`: await a Future, or wrap a deliberate fire-and-forget
  in `unawaited(...)`.
- Before pushing: `flutter analyze` must be clean and `flutter test` must
  pass (CI runs both, then builds the arm64-v8a APK).
- Bump `version:` in `pubspec.yaml` (name and build number) with each
  user-facing change.
- Never commit signing keys or `key.properties` (`docs/SIGNING.md`).
