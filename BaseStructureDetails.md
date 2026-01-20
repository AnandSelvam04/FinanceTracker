# FinanceTracker Structure Snapshot

Current folder layout reflects the working app (expenses, investments, charts, onboarding, backups). Key locations:

```
lib/
  main.dart                 # App entry, providers, theme, onboarding wrapper
  models/                   # Data models (expense, investment, etc.)
  providers/                # ChangeNotifiers (ExpenseProvider, InvestmentProvider)
  services/                 # Data access (DB, storage helpers)
  screens/                  # UI screens (home, add expense/investment, backups, onboarding, expense list)
  widgets/                  # Charts (expense chart, trends) and shared UI components
test/                       # Widget tests
assets/                     # Declared assets
test/                       # Widget tests
.github/                    # Copilot instructions and GitHub configs
pubspec.yaml                # Dependencies and asset registration
android/                    # Platform target (Android only)
```

Packages in use: Flutter 3, Provider, sqflite, path/path_provider, fl_chart, shared_preferences, local_auth, file_picker, csv, google_sign_in, googleapis/googleapis_auth (Drive backup/restore).

Notes:
- Telephony/SMS parsing is intentionally excluded to avoid Play Store permission issues.
- Biometric gate is optional and controlled via SharedPreferences flag (`biometricEnabled`).
- Google Drive backup is implemented; sign-in required, uses appData folder for backup/restore.