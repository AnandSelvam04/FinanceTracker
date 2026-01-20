# Finance Tracker (Flutter)

Android-first Flutter app for tracking expenses, investments, and budgets with a month/year dashboard, charts, and local persistence. Runs with Provider state management and SQLite storage; optional biometric lock. Drive backup/restore is built-in (Google sign-in required), plus local JSON and CSV export.

## Features
- Expense tracking: add expenses with category/date/amount; search/filter in the list view; month and year rollups.
- Dashboard: toggle month/year views, see category breakdowns, and trend chart (last 12 months).
- Investments: capture investment entries from the `Add Investment` tab.
- Budgets: set monthly budgets per category and see spent vs. budget with progress bars.
- Backup/Export: Drive backup/restore (appData storage), local JSON backup/restore, CSV export via file picker + csv.
- Security & onboarding: optional biometric gate with `local_auth` and a first-run tutorial/onboarding flow.

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
  main.dart                 # App entry, providers, theming, onboarding wrapper
  models/                   # Expense, investment, budget models
  providers/                # ExpenseProvider, InvestmentProvider, BudgetProvider
  services/                 # DB and data helpers
  screens/                  # UI screens (home, add expense/investment, budgets, backups, onboarding, list)
  widgets/                  # Charts and shared UI widgets
assets/                     # App assets (declared in pubspec)
android/                  # Platform target (Android only)
```

## Getting started
1) Install Flutter SDK and platform toolchains.
2) From the project root: `flutter pub get`
3) Run on a device/emulator: `flutter run`
4) Static checks: `flutter analyze` (also available as VS Code task `flutter:analyze`).
5) Tests: `flutter test` (uses in-memory sqflite via `sqflite_common_ffi`).

## Configuration notes
- Biometrics: ensure device supports biometrics; toggle via `biometricEnabled` flag in SharedPreferences (set during onboarding).
- Backups to Drive: create OAuth credentials and configure the consent screen before shipping; current packages are present but require proper credentials.
- Budgets: budgets are month- and category-scoped; adjust DB versioning if schema changes further.
- SMS parsing is intentionally not included; telephony dependency is removed to avoid Play Store permission issues.
