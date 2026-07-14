# Finance Tracker (Flutter)

Android-first Flutter app for tracking expenses, income, accounts, investments, and budgets with a month/year dashboard, charts, insights, and local persistence. Runs with Provider state management and SQLite storage; optional app lock. Drive backup/restore is built-in (Google sign-in required), plus local JSON and CSV export.

## Features
- Transactions: record expenses and income with category/date/amount; transfers between accounts; search, type filters, and month/year rollups in the list view.
- Accounts: cash, bank, UPI, and credit-card accounts with opening balances and live computed balances; transfers between them. Each account can be held in its own currency with an exchange rate to the base currency, so balances show in their own currency and net worth/total roll up correctly in the base currency.
- Dashboard: net-worth card (accounts + investments) with a 12-month trend line, proactive budget/bill alerts banner, toggle month/year views, category breakdowns, income totals, and a 12-month trend chart; one-tap quick-add template chips.
- Alerts: dashboard warnings when a budget category reaches 90%/over its cap or a recurring bill is due within three days (toggle in Settings).
- Notifications: optional local push notifications reminding you a day before a bill is due and when a budget limit is hit (rescheduled on each launch; toggle in Settings).
- Recurring: set daily/weekly/monthly/yearly rules that auto-post due transactions on launch (with catch-up); pause or edit any rule.
- Insights: monthly summary (income, expense, net, savings rate, top categories with month-over-month deltas), cash-flow chart, and category trend comparisons.
- Investments: add/list/edit investments with per-type totals.
- Budgets: set monthly budgets per category and see spent vs. budget with progress bars (income and transfers excluded from spend).
- Filter & download: filter the Transactions list by search, year/month, type, category, account, amount range, or a custom date range — then download exactly that set as CSV.
- Backup / Export / Import: Drive backup/restore, versioned local JSON backup/restore, optional passphrase-encrypted backups (AES-256-GCM, PBKDF2), CSV/JSON download via the share sheet, a PDF monthly statement, and CSV import with column mapping and a preview.
- Settings: currency symbol, theme (light/dark/system), budget/bill alerts toggle, auto-lock timeout, and a default account for new transactions.
- Security & onboarding: optional app lock (biometrics or device PIN) that re-locks on resume after a configurable grace period; optional at-rest database encryption (SQLCipher, key held in the device keystore via `flutter_secure_storage`) toggled in Settings with a verify-and-rollback migration; plus a first-run tutorial/onboarding flow.
- Localization: English and Tamil via `flutter_localizations` + a hand-written `AppLocalizations`; navigation, Settings, Accounts, and Budgets screens are localized, with graceful fallback to English for any untranslated key. Add a language by dropping in a locale map.

## Tech stack
- Flutter 3, Provider, sqflite, path/path_provider
- fl_chart for charts
- shared_preferences, local_auth
- file_picker, csv
- google_sign_in, googleapis, googleapis_auth (Drive backup/restore)
- Test support: flutter_test, sqflite_common_ffi (in-memory DB for unit tests)

## Project structure (key paths)
```
lib/
  main.dart                 # App entry, providers, theming, AuthGate, onboarding wrapper
  models/                   # Expense (expense/income/transfer), account, investment, budget, recurring rule, template
  providers/                # Expense, Investment, Budget, Account, Recurring, Template providers
  services/                 # DB (schema v5, migrations), backup, auth, recurring service
  screens/                  # UI screens (home, add expense/transfer, accounts, budgets, recurring, insights, backups, list)
  widgets/                  # Charts (pie, trends, cash flow, category trend), month selector
  utils/                    # DbConstants, category colors, currency format, logger
assets/                     # App assets (declared in pubspec)
android/                  # Platform target (Android only)
```

## Continuous integration
`.github/workflows/ci.yml` runs `flutter analyze` and `flutter test` on every push to `main` and on pull requests.

## Getting started
1) Install Flutter SDK and platform toolchains.
2) From the project root: `flutter pub get`
3) Run on a device/emulator: `flutter run`
4) Static checks: `flutter analyze` (also available as VS Code task `flutter:analyze`).
5) Tests: `flutter test` (uses in-memory sqflite via `sqflite_common_ffi`).

## Configuration notes
- App lock: toggle "App lock" in the More tab (persists `biometricEnabled` in SharedPreferences); falls back to device PIN and shows a retry lock screen instead of exiting on failure.
- Backups to Drive: create OAuth credentials and configure the consent screen before shipping; current packages are present but require proper credentials.
- Budgets: budgets are month- and category-scoped; adjust DB versioning if schema changes further.
- SMS parsing is intentionally not included; telephony dependency is removed to avoid Play Store permission issues.
