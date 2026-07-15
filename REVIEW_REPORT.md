# Application Review & Improvement Analysis

_Updated: July 2026 (branch `claude/app-improvement-analysis-2q29is`)._

> **Implementation status:** every item below has been implemented on this
> branch (`flutter analyze` clean, 84 tests passing).
>
> - 1.1 ✅ pre-migration snapshot deleted after a verified cipher migration;
>   auto-backups are encrypted with the device key while DB encryption is on
> - 1.2 ✅ transfers carry a destination-currency `toAmount` (schema v8); the
>   add/edit transfer UIs show a received-amount field when currencies differ
> - 1.3 ✅ `netWorthSeries` converts every account at its exchange rate and
>   now runs on 3 grouped queries instead of 36
> - 1.4 ✅ restore runs in one DB transaction (corrupt backup = no data loss)
> - 1.5 ✅ Drive backup updates the existing file and prunes stale duplicates
> - 1.6 ✅ recurring catch-up posts occurrences + advances `nextDue` atomically
> - 1.7 ✅ deleting an account also detaches recurring rules and templates
> - 2.1 ✅ tabs render in an `IndexedStack`; also fixed: selecting an older
>   year (or a custom date range) now loads that data on demand
> - 2.2 ✅ dashboard, transactions screen, edit sheets, snackbars, lock
>   screen, and notifications localized (en + ta); remaining English-only
>   screens: investments, recurring, backups, import, summary, cashflow
> - 2.3 ✅ Material 3 `ColorScheme.fromSeed` in both modes; shared
>   theme-aware semantic colors replace fixed light-mode shades
> - 2.4 ✅ indexes on `expenses(date)`, `(type, accountId)`, `(toAccountId)`;
>   all account balances computed in one grouped pass
> - 2.5 ✅ quick-add undo uses the inserted row id; decimal-aware keyboards
>   in edit/filter sheets; year filter derives from actual data; budget
>   notification ids come from a persistent map (no hash collisions)
> - 3 ✅ `flutter_lints` moved to dev_dependencies; release signing reads
>   `android/key.properties` with a debug-key fallback

## Overview

The app is in good shape. Every action item from the previous review has been
completed: SQL date-range filtering with per-year lazy loading
(`getExpensesByYear` / `ensureYearLoaded`), a 3-tab bottom bar plus a FAB for
adding transactions, DB strings extracted to `DbConstants`, and error handling
with `AppLogger` instead of `print`. On top of that the app has since gained
minor-unit (integer) money storage, multi-currency accounts, SQLCipher at-rest
encryption with verify-and-rollback migration, encrypted backups, recurring
transactions, notifications, localization (en/ta), and a broad test suite with
CI that analyzes, tests, and builds APKs.

The findings below are what remains. They are ordered by priority.

## 1. Correctness & data safety (high priority)

### 1.1 Plaintext leftovers undermine the SQLCipher encryption
- `DBService._writeSafetySnapshot` writes the **entire database as plaintext
  JSON** to `finance_pre_migration.json` before an encryption migration, and
  the file is **never deleted after a successful migration**
  (`lib/services/db_service.dart:453`). A user who enables encryption ends up
  with an encrypted DB sitting next to a full plaintext copy of it, forever.
- `BackupService.autoBackupIfDue` writes a **plaintext** `finance_backup.json`
  every day regardless of whether DB encryption is on
  (`lib/services/backup_service.dart:130`).

**Fix:** delete the safety snapshot at the end of a successful
`enableEncryption`/`disableEncryption`, and when DB encryption is enabled,
route the auto-backup through the encrypted envelope (the device key in
`flutter_secure_storage` can encrypt it — no passphrase prompt needed).

### 1.2 Cross-currency transfers corrupt account balances
A transfer stores a single `amount`, and `getAccountBalance` subtracts it from
the source and adds it to the destination **without any currency conversion**
(`lib/services/db_service.dart:741-752`). Transferring between accounts held
in different currencies credits the destination with the wrong number of
units (e.g. sending ₹8,300 from an INR account to a USD account adds
"8,300" to the USD balance instead of ~100).

**Fix options:** either store the amount in both currencies on the transfer
row (add a `toAmount` column) or convert via the two accounts' rates at
posting time; at minimum, warn/convert in the transfer UI when the accounts'
currencies differ.

### 1.3 Net-worth trend ignores exchange rates (inconsistent with the headline)
The headline net-worth figure converts each account to the base currency
(`AccountProvider.totalBaseBalance`), but the 12-month trend on the same card
uses `DBService.netWorthSeries`, which sums opening balances and transaction
amounts **raw, with no rate applied**
(`lib/services/db_service.dart:679-719`). With any foreign-currency account,
the headline and the trend line on the same card disagree. Category totals,
monthly summaries, and budget "spent" have the same blind spot for
transactions on foreign-currency accounts.

**Fix:** apply account rates in `netWorthSeries` (join expenses to accounts),
and decide/document one rule for reports: convert at the account rate
everywhere a base-currency total is shown.

### 1.4 Backup restore is not atomic
`_applyRestore` calls `clearAll()` and then inserts every row one `await` at a
time with no transaction (`lib/services/backup_service.dart:212`). If the app
is killed or a malformed row throws mid-restore, the user is left with a
half-empty database — and the wipe has already happened. It is also slow for
large backups.

**Fix:** wrap the clear + inserts in a single `db.transaction` (or batch), so
a failed restore rolls back to the pre-restore state.

### 1.5 Drive backups accumulate forever
`backupToDrive` always calls `driveApi.files.create`, so every backup adds a
new `finance_backup.json` to the app-data folder and old copies are never
updated or deleted (`lib/services/backup_service.dart:272`). Restore picks the
newest so it still works, but the user's Drive quota fills with dead copies.

**Fix:** look up the existing file id and `files.update` it, or delete older
copies after a successful upload.

### 1.6 Recurring catch-up can double-post after a crash
`postDueTransactions` inserts all due occurrences for a rule and only
afterwards updates the rule's `nextDue`
(`lib/services/recurring_service.dart:52-72`). A crash between the inserts
and the rule update re-posts the same occurrences on the next launch.

**Fix:** wrap each rule's inserts + rule update in one transaction.

### 1.7 Deleting an account leaves dangling references in rules/templates
`deleteAccount` nulls `accountId`/`toAccountId` on transactions but does not
touch `recurring_rules` or `templates`
(`lib/services/db_service.dart:596-614`), so rules keep posting transactions
into a deleted account id.

**Fix:** null out (or block deletion while referenced by) rule/template
`accountId` in the same operation.

## 2. UX & polish (medium priority)

### 2.1 Tab switches lose the Transactions screen's state
`HomeScreen` swaps `body: _screens[_selectedIndex]`
(`lib/screens/home_screen.dart:244`), which unmounts the list screen when the
user visits another tab — search text, filters, and scroll position reset.
Use an `IndexedStack` (or `PageStorage`) to preserve state across tabs.

### 2.2 Localization is incomplete
Tamil users get a mixed-language UI. Still hardcoded English: the dashboard
("View:", "Month"/"Year", "No expenses this month.", "Quick add",
"Year Total:", "Income:", "Trends…", "Net Worth", "No history yet"), the
entire Transactions screen (title, search, filters sheet, edit sheets, delete
dialog, empty state), snackbars ("Posted N recurring transactions",
"Added …", "Undo"), and notification texts ("Bill due soon", "Over budget").
The `AppLocalizations` scaffolding exists — this is mostly key-plumbing work.

### 2.3 Material 3 / dark-theme consistency
`main.dart` uses M2-style `primarySwatch: Colors.green` for light and a bare
`ThemeData(brightness: Brightness.dark)` for dark, so dark mode loses the
brand color entirely (`lib/main.dart:68-74`). Widgets also hardcode
`Colors.red.shade50`, `Colors.grey.shade600`, etc., which have poor contrast
on dark backgrounds. Switch both themes to
`ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(...))` and
take colors from `Theme.of(context).colorScheme`.

### 2.4 Performance niceties
- No indexes exist on `expenses(date)` or `expenses(type, accountId)`; every
  balance refresh runs four full-table scans **per account**, serially
  (`getAccountBalance`). One `GROUP BY accountId, type` query could compute
  all balances in a single pass, and a date index makes the year queries and
  net-worth series cheap as data grows.
- `netWorthSeries` runs 3 queries × 12 months = 36 queries per dashboard
  build; a single grouped-by-month query would do.

### 2.5 Small UX gaps
- Quick-add "Undo" re-finds the inserted row by matching description, amount
  and date (`lib/screens/home_screen.dart:143`) — fragile with duplicates.
  `insertExpense` already returns the new id; plumb it through `addExpense`.
- The Transactions year dropdown is hardcoded to the last 10 years
  (`lib/screens/expense_list_screen.dart:505`); older imported data becomes
  unreachable. Derive the range from the earliest transaction.
- Amount fields in the edit sheets use `TextInputType.number`, which hides
  the decimal point on some keyboards; use
  `TextInputType.numberWithOptions(decimal: true)` (the Add screens already
  do this).
- Budget notification ids use `category.hashCode % 1000`
  (`lib/services/notification_service.dart:149`) — two categories can
  collide and overwrite each other's notification.

## 3. Hygiene (low priority)

- `flutter_lints` is under `dependencies` in `pubspec.yaml`; it belongs in
  `dev_dependencies`.
- Release APKs are signed with the debug key (noted in CI comments) — fine
  for testing, a blocker for Play distribution; add a proper signing config
  gated on a secret before shipping.
- `REVIEW_REPORT.md` (this file) previously described already-completed work;
  keep it current or fold it into issues so it doesn't mislead contributors.

## Suggested order of attack

1. Delete the plaintext migration snapshot + encrypt auto-backups (1.1) —
   small change, biggest safety payoff.
2. Make restore and recurring posting transactional (1.4, 1.6).
3. Fix cross-currency transfers and the net-worth series conversion
   (1.2, 1.3) — decide the conversion rule once, apply everywhere.
4. Drive backup update-instead-of-create (1.5) and account-deletion cleanup
   (1.7).
5. IndexedStack tabs, finish localization, Material 3 theme (2.1–2.3).
6. Indexes + single-pass balance query (2.4), then the small UX items (2.5)
   and hygiene fixes (3).
