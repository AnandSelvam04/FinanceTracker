# Finance Tracker (Flutter)

Android-first Flutter app for tracking expenses, income, accounts, investments, and budgets with a month/year dashboard, charts, insights, and local persistence. Runs with Provider state management and SQLite storage; optional app lock. Drive backup/restore is built-in (Google sign-in required), plus local JSON and CSV export.

## Features
- Transactions: record expenses and income with category/date/amount; transfers between accounts (including cross-currency transfers with a destination-side amount); search, type filters, and month/year rollups in the list view.
- Accounts: cash, bank, UPI, and credit-card accounts with opening balances and live computed balances; transfers between them. Each account can be held in its own currency with an exchange rate to the base currency, so balances show in their own currency and net worth/total roll up correctly in the base currency.
- Dashboard: net-worth card (accounts + investments) with a 12-month trend line, proactive budget/bill alerts banner, toggle month/year views, category breakdowns, income totals, and a 12-month trend chart; one-tap quick-add template chips.
- Alerts: dashboard warnings when a budget category reaches 90%/over its cap or a recurring bill is due within three days (toggle in Settings).
- Notifications: optional local push notifications reminding you a day before a bill is due and when a budget limit is hit (rescheduled on each launch; toggle in Settings).
- Recurring: set daily/weekly/monthly/yearly rules that auto-post due transactions on launch (with catch-up); pause or edit any rule.
- Insights: monthly summary (income, expense, net, savings rate, top categories with month-over-month deltas), cash-flow chart, and category trend comparisons.
- Investments: add/list/edit investments with per-type totals.
- Budgets: set monthly budgets per category and see spent vs. budget with progress bars (income and transfers excluded from spend).
- SMS import: scans the last 90 days of the SMS inbox for bank transaction alerts, parses out amount, direction, merchant, and date, and routes each one to the account whose last-4 digits the message names. Everything lands in a review queue — nothing posts to the ledger without confirmation. Imported and dismissed messages are remembered, so a rescan never offers the same one twice.
- Filter & download: filter the Transactions list by search, year/month, type, category, account, amount range, or a custom date range — then download exactly that set as CSV.
- Backup / Export / Import: Drive backup/restore, versioned local JSON backup/restore, optional passphrase-encrypted backups (AES-256-GCM, PBKDF2), CSV/JSON download via the share sheet, a PDF monthly statement, and CSV import with column mapping and a preview.
- Settings: currency symbol, theme (light/dark/system), budget/bill alerts toggle, auto-lock timeout, and a default account for new transactions.
- Security & onboarding: optional app lock (biometrics or device PIN) that re-locks on resume after a configurable grace period; optional at-rest database encryption (SQLCipher, key held in the device keystore via `flutter_secure_storage`) toggled in Settings with a verify-and-rollback migration; plus a first-run tutorial/onboarding flow. Automatic Android backup is disabled and `FLAG_SECURE` is set, so the database never syncs off-device on its own and balances stay out of the recents thumbnail.
- Multi-currency: accounts can be held in a currency other than the base one, with a per-account exchange rate. Amounts are stored in their source account's currency; every base-currency total (dashboard, budgets, net worth, PDF statement) converts at that rate.

## Tech stack
- Flutter 3, Provider, `sqflite_sqlcipher`, path/path_provider
- fl_chart for charts
- shared_preferences, local_auth
- file_picker, csv
- another_telephony (SMS inbox reading, Android only)
- google_sign_in, googleapis, googleapis_auth (Drive backup/restore)
- Test support: flutter_test, sqflite_common_ffi (file-backed SQLite for unit tests)

## Project structure (key paths)
```
lib/
  main.dart                 # App entry, providers, theming, AuthGate, onboarding wrapper
  models/                   # Expense (expense/income/transfer), account, investment, budget, recurring rule, template
  providers/                # Expense, Investment, Budget, Account, Recurring, Template providers
  services/                 # DB (schema v10, migrations), backup + crypto, auth, notifications, recurring, CSV + SMS import, PDF statement
  screens/                  # UI screens (home, add expense/transfer, accounts, budgets, recurring, insights, backups, list)
  widgets/                  # Charts (pie, trends, cash flow, category trend), month selector
  utils/                    # DbConstants, category colors, currency format, logger
assets/                     # App assets (declared in pubspec)
android/                  # Platform target (Android only)
```

## Continuous integration
`.github/workflows/ci.yml` runs `flutter analyze` and `flutter test`, then builds split-per-ABI release APKs and uploads them as artifacts (14-day retention), on every push to `main` and on pull requests.

Both jobs are gated on `github.event.repository.private == false`, so GitHub Actions minutes are never billed. Note the consequence: if the repository is ever made private, CI is skipped silently — no failed check, just no checks at all.

## Getting started
1) Install Flutter SDK and platform toolchains.
2) From the project root: `flutter pub get`
3) Run on a device/emulator: `flutter run`
4) Static checks: `flutter analyze` (also available as VS Code task `flutter:analyze`).
5) Tests: `flutter test` (runs against file-backed SQLite via `sqflite_common_ffi`; each test file isolates its own database with `DBService.dbNameOverride`).

## Configuration notes
- App lock: toggle "App lock" in the More tab (persists `biometricEnabled` in SharedPreferences); falls back to device PIN and shows a retry lock screen instead of exiting on failure.
- Backups to Drive: create OAuth credentials and configure the consent screen before shipping; current packages are present but require proper credentials.
- Budgets: budgets are month- and category-scoped; adjust DB versioning if schema changes further.
- Release signing: `android/key.properties` and the keystore are committed on purpose, so the Drive OAuth SHA-1 stays stable across rebuilds. See the comment in `android/app/build.gradle.kts` for what that trades away — do not copy the pattern for a Play Store release.
- SMS import: needs the `READ_SMS` runtime permission, granted on first use of **More > Import from SMS**. Messages are parsed entirely on-device and never leave it.

  Declaring `READ_SMS` makes the app ineligible for Play Store distribution — store policy restricts that permission to apps whose core function is SMS handling. This build is signed and sideloaded (see the release-signing note above), so that is a deliberate trade rather than an oversight. Removing the permission from `AndroidManifest.xml` and the `another_telephony` dependency from `pubspec.yaml` reverts it; the rest of the app is unaffected.

  Parsing quality depends on templates banks change without notice, which is why nothing auto-posts. `lib/services/sms_import.dart` holds the patterns and is pure Dart — add a bank's wording there and cover it in `test/sms_import_test.dart`. Accuracy against the current formats is pinned down by those tests; the plugin layer in `lib/services/sms_service.dart` is thin and can only be verified on a real device.

  Account routing needs each account's last four digits filled in (Accounts > tap an account > *Last 4 digits*). Without them a parsed message still imports, but with no account attached, so it will not move any balance.
