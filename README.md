# Personal Finance Tracker — Android (Flutter)  
**Project:** Personal Finance Tracker (Android-only, Flutter)  
**Backup:** Local SQLite + Local JSON + Manual Google Drive backup/restore (Option A)  
**Created:** 2025-11-23

---

## Overview
This Android-first Flutter app helps you track personal expenses (credit card, debit card, cash), investments (Mutual Funds, NPS), and provides a dashboard, charts, and backups. It supports **manual entry** and **automatic SMS parsing** for bank/card messages (Android only).

Key features:
- Manual expense & investment entry
- SMS parsing to auto-add transactions (Telephony plugin)
- Local offline storage using SQLite (`finance.db`)
- Local JSON backups (auto daily + manual)
- Manual Google Drive backup & restore (uploads/downloads `finance.db`)
- Export to CSV (optional)
- PIN/biometric lock (optional)

---

## Project structure (recommended)
```
lib/
  main.dart
  models/
    expense.dart
    investment.dart
  services/
    db_service.dart
    sms_service.dart
    backup_service.dart
  providers/
    expense_provider.dart
    investment_provider.dart
  screens/
    home_screen.dart
    add_expense_screen.dart
    add_investment_screen.dart
    backups_screen.dart
  widgets/
    expense_tile.dart
    investment_tile.dart
android/
  app/
    src/main/AndroidManifest.xml
    ...
pubspec.yaml
```

---

## Dependencies (pubspec.yaml)
Add these dependencies (versions may change — use latest compatible):
```yaml
dependencies:
  flutter:
    sdk: flutter
  sqflite: ^2.2.8
  path_provider: ^2.0.15
  provider: ^6.0.5
  intl: ^0.18.1
  fl_chart: ^0.55.1
  telephony: ^0.0.5
  permission_handler: ^10.4.0
  csv: ^5.0.0
  google_sign_in: ^5.4.2
  googleapis: any
  googleapis_auth: any
```

> Note: `googleapis` and `googleapis_auth` are used to access Google Drive API. You will need to configure OAuth credentials in Google Cloud Console and create an **OAuth Client ID (Android)** using your app package name and SHA-1.

---

## Android permissions
Update `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.RECEIVE_SMS" />
<uses-permission android:name="android.permission.READ_SMS" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
```
> Google Play restricts SMS permissions. For Play Store publishing, use proper declarations or avoid READ_SMS/RECEIVE_SMS. For personal use or sideloading, these permissions work.

---

## Local DB & Reloading data
- SQLite DB file: `/data/data/<package>/databases/finance.db`
- App loads data on startup (example):
```dart
ChangeNotifierProvider(create: (_) => ExpenseProvider()..load())
```
- To preserve data across reinstall, use Google Drive backup or export the `finance.db` file manually.

---

## Backup & Restore (Manual Google Drive)
1. Create an OAuth 2.0 Client ID (type: Android) in Google Cloud Console.
   - Enter your app package name (e.g., `com.example.personal_finance_tracker`)
   - Add SHA-1 fingerprint (from your debug/release keystore)
2. In your Flutter app, use `google_sign_in` to sign in and then `googleapis/drive.v3` to upload/download the `finance.db` file.
3. Upload path: app will store the file under user's Drive root or a specific app folder.
4. On Restore: download the file and replace local DB, then reload providers.

Security note: Never store service-account keys in the app. Use OAuth interactive sign-in.

---

## Local JSON Backup Strategy
- Daily auto-backup: export all transactions/investments into a compact JSON (timestamps + minimal fields).
- Save location: `getExternalStorageDirectory()` or app directory (Android/data/...)
- Keep N versions (e.g., last 7 backups) and optionally size-limit them.

Example file name:
```
backup_YYYYMMDD_HHMM.json
finance.db
```

---

## SMS Parsing & Telephony
- Use `telephony` plugin to listen for incoming SMS.
- Implement robust regex-based parsers per bank (HDFC, SBI, ICICI, Axis, PhonePe, Google Pay).
- Map merchant names to categories (Amazon -> Shopping).

Example regex for debit:
```
(debited|withdrawn|spent|purchase|tx of|debit)\s+.*?(Rs\.?|INR)?\s?(\d+\.?\d*)
```

---

## Google Drive Setup (Quick)
1. Go to Google Cloud Console → APIs & Services → Credentials.
2. Create OAuth 2.0 Client ID → choose Android.
3. Provide package name and SHA-1 fingerprint.
   - Get SHA-1 (debug): `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android`
4. Enable Drive API for the project.
5. In app, use `google_sign_in` scopes:
```dart
final GoogleSignIn _googleSignIn = GoogleSignIn(
  scopes: [DriveApi.driveFileScope, DriveApi.driveAppdataScope],
);
```
6. Use `DriveApi` from `googleapis` to upload/download the DB file.

---

## Backup/Restore UX (recommended)
- Settings → Backups
  - Backup now (upload finance.db)
  - Restore from Drive (choose file)
  - Export JSON
  - Import JSON
  - Auto JSON backup toggle (daily)
  - Keep last N backups (configurable)

---

## Build & Run (Debug)
1. Connect Android device (or emulator).
2. `flutter pub get`
3. `flutter run --release` (for production) or `flutter run` (debug)
4. For release, configure `android/app/build.gradle` with your signing configs.

---

## Publishing notes
- Avoid using SMS permissions if you want to publish on Play Store — Play Store has strict policies; you must apply for permission declarations or remove SMS features.
- Consider SHA-256 certificate for Play App Signing.

---

## Next steps I can help with
- Add BackupService code (Google Drive + JSON) into the project files.
- Generate downloadable ZIP of the full Flutter project scaffold.
- Improve SMS parser for Indian bank templates.
- Add investment screens + NAV fetch.

---

If you want, I will now generate the `README.md` and a step-by-step `.docx` with detailed instructions for creating the application and provide download links.
