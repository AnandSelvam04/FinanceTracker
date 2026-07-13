# Finance Tracker (Flutter)

Android-first Flutter app for tracking expenses, income, accounts, investments, and budgets with a month/year dashboard, charts, insights, and local persistence. Runs with Provider state management and SQLite storage; optional app lock. Drive backup/restore is built-in (Google sign-in required), plus local JSON and CSV export.

## Features
- Transactions: record expenses and income with category/date/amount; transfers between accounts; search, type filters, and month/year rollups in the list view.
- Accounts: cash, bank, UPI, and credit-card accounts with opening balances and live computed balances; transfers between them.
- Dashboard: toggle month/year views, category breakdowns, income totals, and a 12-month trend chart; one-tap quick-add template chips.
- Recurring: set daily/weekly/monthly/yearly rules that auto-post due transactions on launch (with catch-up); pause or edit any rule.
- Insights: monthly summary (income, expense, net, savings rate, top categories with month-over-month deltas), cash-flow chart, and category trend comparisons.
- Investments: add/list/edit investments with per-type totals.
- Budgets: set monthly budgets per category and see spent vs. budget with progress bars (income and transfers excluded from spend).
- Backup/Export: Drive backup/restore (appData storage), local JSON backup/restore (versioned, backward compatible), CSV export.
- Security & onboarding: optional app lock (biometrics or device PIN) with a retry lock screen, plus a first-run tutorial/onboarding flow.

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
