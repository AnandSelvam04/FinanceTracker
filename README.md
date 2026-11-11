# Finance Tracker (Flutter)

Android-first Flutter app for tracking expenses, income, accounts, investments, and budgets with a month/year dashboard, charts, insights, and local persistence. Runs with Provider state management and SQLite storage; optional app lock. Drive backup/restore is built-in (Google sign-in required), plus local JSON and CSV export.

## Features
- Transactions: record expenses and income with category/date/amount (the category is picked from chips or a searchable list, where a new one is created on purpose, so a typo cannot start a second category); transfers between accounts (including cross-currency transfers with a destination-side amount); search, type filters, and month/year rollups in the list view. The list groups rows under Today / Yesterday / date headers with each day's spend, and leads with the spent and income totals for whatever the current filters show.
- Quick capture: scan a bill/receipt photo (camera or gallery) and read its amount, date, and merchant with on-device OCR (ML Kit), or dictate a transaction by voice ("spent 250 on food at Dominos") with on-device speech recognition. Both only pre-fill the Add Expense form — nothing is saved without review. Both run entirely on-device; the photo and audio never leave it.
- Reports (More → Reports): view figures by **week, month, year or any dates you pick**. The **year** view is a year in review — spending month by month (tap a bar to open that month), the average month, the highest and lowest, the month most was saved, the biggest expense and the no-spend days. Any period shares as a **PDF** (a year or custom period adds month-by-month and per-category tables) or as an **Excel workbook** with Summary, Transactions, By category and By month sheets, with real dates and numbers so it sorts and sums. In every view you can filter the whole summary to a single **category** to drill into just its transactions; top categories show a share-of-spend progress bar with a period-over-period delta. **Top merchants** ranks where the money went by payee (spellings like "Swiggy" and "SWIGGY 88213" count as one, refunds come off); tap one to see the transactions behind its total.
- Accounts: cash, bank, UPI, and credit-card accounts with opening balances and live computed balances; transfers between them. Tap an account for its statement: every transaction, transfer and investment that moved it (all years), each with the running balance after it, down to the opening balance. Credit cards can carry a **billing cycle** (statement day + payment due day); the app then tracks the amount billed on the last statement and reminds you before it's due. Two cards a bank issues on **one shared limit** (a Visa/Mastercard and a RuPay card, as HDFC and Scapia do) can be linked in one tap: the Credit cards screen suggests pairs from the same bank (**Link them**), a card's ⋮ menu offers **Add a card on this limit**, and the card set-up has an **Own limit / Shared** switch. Linked cards show together under one shared-limit bar: both then show the same limit and what is left of it — a ₹2,00,000 limit with ₹10,000 on one card and ₹5,000 on the other shows ₹1,85,000 available on both — while each card keeps its own spending, statement and bill. Each account can be held in its own currency with an exchange rate to the base currency, so balances show in their own currency and net worth/total roll up correctly in the base currency.
- Credit cards (More → Cards): per card, what was spent over a cycle or any period, what is owed (with a **Why owed?** breakdown that adds up to it: starting amount, earlier unpaid spending, this cycle's spending and payments), the limit used, the bill and its due date with an estimated **minimum due**, and when a purchase made today would have to be paid (**interest-free days**). With two or more cards, a banner names the **best card to use today**. Cards on one shared limit (Visa + RuPay) show together under one bar. The bank's **Avl Lmt** from card SMS is checked against the app's figure, with a one-tap **Match bank**.
- Match bank balance: on any account's statement or a card's menu, enter what the bank shows (or a card's available limit) and the account's starting balance moves by the difference — transactions, spending and budgets are untouched.
- Card EMIs: convert a card purchase to EMI (amount, 3–36 months, monthly EMI). The purchase comes off the card; each instalment is posted on its date onto the card's bill (principal as a transfer, interest as an *EMI interest* expense), and the unpaid principal stays held against the limit.
- Loans & lending (More): money you owe (a personal loan, borrowed from a friend) and money owed to you, as `loan` / `lent` accounts. Borrowing, lending and repaying are transfers, so balances and net worth stay right and none of it counts as spending; each shows what is left and a repaid-so-far bar.
- Reward points: per card, a points balance, points per ₹100 and value per point; the screen adds what spending since has earned, and a newer balance quoted in a card SMS replaces the one typed in.
- Receipt photos & tags: a scanned bill's photo is kept with its transaction (view, attach, replace or remove it from the edit sheet; a paperclip marks it in the list). Photos stay in the app's private storage and are not part of backups. Write `#tags` in a note to group spending; More → Tags totals each tag across categories and months.
- Home-screen widget (Android): this month's and today's spending with an Add button. Figures are hidden while app lock is on.
- Navigation: a bottom bar with Home, Activity (transactions), **Add**, Budgets and More, every tab labelled; each tab has a single app bar of its own. On a tablet or a phone held sideways (720dp and wider) the tabs move to a rail down the side and the dashboard splits into two columns, figures on the left and charts on the right. **More** opens with a search box that finds any screen or setting by name ("backup", "theme", "cards").
- Calculator in amount fields: every amount accepts a sum — `250+80`, `1200/3`, `(450+90)*2` — and saves its result. Add Expense and the edit sheet carry **+ − × ÷** keys under the amount (the number keyboard has none) with the running answer beside them; tap it to replace the sum with the figure.
- Customise home (More → Customise home): drag the dashboard's sections into the order you want, switch off the ones you don't use, and pick up to four shortcut buttons (Investments, Cards, Import SMS, Reports, Accounts, Goals, Calendar, Loans, Recurring, Cash flow). The layout is kept in preferences and travels in backups.
- Insights on Home: up to three plain-language lines about the month on show — where the overall budget is heading ("At this pace you'll end the month ₹4,200 under budget"), the category that moved most ("Food is up 23% on by this day last month"), how total spending compares, the share of income kept, and the biggest expense. The month in progress is compared with the same days of the month before, not the whole of it. With an overall budget set, a **budget ring** under the month's total shows the share used and what is left (tap for the Budgets tab), and two or more days without spending show as a **no-spend streak**.
- App-icon shortcuts (Android): long-press the launcher icon for **Add expense**, **Scan receipt** and **Add by voice**.
- Swipe actions: on budgets, recurring rules, savings goals and accounts, swipe left to delete (each with its usual confirmation) and right to edit — as on transactions. The same actions are published to screen readers.
- Celebrations: reaching a savings goal, clearing a loan, and the first launch after a month that ended within its overall budget are marked with a burst of confetti (skipped when the phone asks for reduced motion).
- What's new: after an update, a sheet lists what changed, once; it stays under Settings → What's new.
- Dashboard: net-worth card (accounts + investments) with a 12-month trend line, proactive budget/bill alerts banner, toggle month/year views (the stepper moves by year in Year view), income totals, shortcuts and the five most recent transactions straight after the period's figures, then category breakdowns, the period's top three merchants (tap for their transactions) and a 12-month trend chart; one-tap quick-add template chips. The + button offers expense/income, receipt scan, voice, transfer, and investment.
- Alerts: dashboard warnings when a budget category reaches 90%/over its cap, a recurring bill is due within three days, or a credit-card statement is coming due (toggle in Settings).
- Notifications: an optional daily reminder at a time you pick to log the day's spending (skipped on days you've already added something), plus optional local push notifications reminding you a day before a bill is due, a few days before a credit-card payment is due (with the statement amount), and when a budget limit is hit (rescheduled on each launch; toggle in Settings).
- Recurring: set daily/weekly/monthly/yearly rules that auto-post due transactions on launch (with catch-up); pause or edit any rule.
- Spending calendar: More → Spending Calendar shows a month as a calendar with each day shaded by how much went out (refunds netted), plus the month's spend, daily average, no-spend days and biggest day; tap a day for its transactions.
- Insights: monthly summary (income, expense, net, savings rate, spend split per account with each one's share, top categories with month-over-month deltas), cash-flow chart, and category trend comparisons.
- Investments: add/list/edit investments with per-type totals; record a withdrawal to take money back out of a holding (stored as a negative contribution, so the type total and net worth fall); and move a whole type's contributions to another type from the type detail screen when one was filed under the wrong category. The investments screen shows an allocation bar and each type's share of the total.
- Categories: More → Categories lists each expense/income category with how many transactions use it. Add your own, give any category an icon and colour, rename one, or give it another's name to merge the two; removing one that is in use first moves its transactions to a category you pick. Your categories and their looks are kept in preferences and travel in backups. Transactions, budgets (caps colliding in a month are summed), recurring rules and quick-add templates move together.
- Budgets (its own bottom tab): set monthly budgets per category and see spent vs. budget with progress bars (income and transfers excluded from spend). Step between months; for the current month each cap shows a month-end pace forecast — an early warning when today's pace would break the cap, otherwise how much is left to spend per day. Optional **rollover** (Budgets menu or Settings, off by default) carries what's left of a cap — or its overspend — into the next month's cap for the same category, through up to 12 consecutive months that have one; the screen, the dashboard alerts and the notifications all measure against the rolled-over cap.
- Savings goals: set a target amount with an optional target date, add or withdraw money toward it (with undo), and see progress plus the monthly amount needed to hit the date. Goals earmark money rather than moving it, so account balances and net worth are unaffected. Included in backups.
- SMS import: off by default; enable **Read SMS for transactions** in Settings. With **Notify me as transactions arrive** also on (off by default; needs the RECEIVE_SMS and notification permissions), a bank alert raises a notification the moment it arrives — "Spent ₹450.00 · Swiggy" — even while the app is closed; tapping it opens the review queue. The notification records nothing: the message goes through the same review as any other. Scans the SMS inbox for bank transaction alerts since the review queue was last cleared (at least 2 days, at most 30), parses out amount, currency, direction, merchant, payment mode, and date, and routes each one to the account whose last-4 digits the message names (saying so when several accounts share them). The dashboard's Import SMS shortcut shows how many new alerts are waiting. Money moving between your own accounts (a card bill paid from a bank, an NEFT between banks) is detected from the from/to pair and recorded as a transfer rather than as spending, and the two alerts one movement sends are collapsed into a single row. A credit card bill payment is recorded as a transfer from the bank to the card, whichever side texts about it: a credit on the card that isn't a refund or cashback (asking which account paid), or a bank debit "towards Credit Card bill" / "paid to CRED" that names no card (picking your card when you have one, else asking) — so the bill counts as neither income nor a second round of spending. Refunds are saved as negative expenses, so they come off the purchase's category (and its budget) instead of counting as income. A charge in a foreign currency ("USD 12.99") is left unchecked until its amount in the account's currency is entered. Candidates that match a transaction you already entered by hand are flagged and left unchecked; one hand-entered row is matched to at most one alert, preferring the one naming the same merchant. Categories are recalled from how the same merchant was filed before, or guessed from well-known merchant names (Swiggy → Food, Uber → Transport, …), so most arrive ready to import. Debits to investment platforms (Zerodha, Groww, SIPs, mutual funds, NPS, digital gold, …) arrive already set to **Investment** with the type guessed, paid from the account the message names; a merchant you import as an investment is remembered with its type and holding name, and any debit or bank-to-bank move can be switched between Expense/Transfer and Investment at the top of its card. **Always ignore** hides a merchant's alerts for good (undo under *Ignored merchants* in the menu). Everything lands in a review queue — nothing posts to the ledger without confirmation, and the queue's bulk bar can select all, set one account for the batch, or dismiss every selected message at once (with a single Undo). Imported and dismissed messages are remembered, so a rescan never offers the same one twice.
- Transactions tab: pick a year and month or **All years** (a search that finds nothing in the year on show offers to look through all of them); sort newest first (grouped by day) or largest first; long-press a row to select several, then change their category or delete them together (with Undo). Each transaction can carry an optional note, shown under it in the list and found by search.
- Hide amounts: the eye button on the home screen masks every figure on screen (for opening the app in front of others); PDF statements, CSV exports and notifications keep the real figures.
- Filter & download: filter the Transactions list by search, year/month, type, category, account, amount range, or a custom date range — then download exactly that set as CSV.
- Backup / Export / Import (grouped as Back up, Restore and Export & import, with the on-device copy and sealed files under More options): Drive backup/restore, with optional **automatic Drive backup** (Backups screen switch, off by default: once a day at launch to the signed-in account, never prompting for sign-in, sealed with a passphrase kept in the device keystore when the database is encrypted, and never overwriting a newer copy another phone saved — or uploading when it cannot tell), versioned local JSON backup/restore, optional passphrase-encrypted backups (AES-256-GCM, PBKDF2), CSV/JSON download via the share sheet, **Download everything (Excel)**, a PDF monthly statement, and CSV import with column mapping and a preview (credits described as a refund, reversal or chargeback import as refunds — negative expenses that come off their category — not as income).
- Settings: currency symbol, theme (light/dark/system, with an optional **true black** dark theme for OLED screens), accent colour (seven to choose from, or **Match my wallpaper** on Android 12+), budget/bill alerts toggle, SMS-import toggle (off by default), auto-lock timeout, and a default account for new transactions.
- Security & onboarding: optional app lock (biometrics or device PIN) that re-locks on resume after a configurable grace period; optional at-rest database encryption (SQLCipher, key held in the device keystore via `flutter_secure_storage`) toggled in Settings with a verify-and-rollback migration; plus a first-run set-up (currency, a first account, SMS import and app lock — each optional) and a How to use guide. Automatic Android backup is disabled and `FLAG_SECURE` is set, so the database never syncs off-device on its own and balances stay out of the recents thumbnail.
- Multi-currency: accounts can be held in a currency other than the base one, with a per-account exchange rate. Amounts are stored in their source account's currency; every base-currency total (dashboard, budgets, net worth, PDF statement) converts at that rate.

## Tech stack
- Flutter 3, Provider, `sqflite_sqlcipher`, path/path_provider
- fl_chart for charts
- shared_preferences, local_auth, package_info_plus
- file_picker, csv
- another_telephony (SMS inbox reading and incoming-SMS listening, Android only)
- archive (zips the sheets of an Excel export)
- home_widget (home-screen widget, Android)
- image_picker, google_mlkit_text_recognition (on-device receipt OCR)
- speech_to_text (on-device voice entry; requires the RECORD_AUDIO permission)
- google_sign_in, googleapis, googleapis_auth (Drive backup/restore)
- Test support: flutter_test, sqflite_common_ffi (file-backed SQLite for unit tests)

## Project structure (key paths)
```
lib/
  main.dart                 # App entry, providers, theming, AuthGate, onboarding wrapper
  models/                   # Expense (expense/income/transfer), account, investment, budget, recurring rule, template, savings goal
  providers/                # Expense, Investment, Budget, Account, Recurring, Template, Goal providers
  services/                 # DB (schema v22, migrations), backup + crypto, auth, notifications, recurring, CSV + SMS import, PDF statement
    db/                     # DbSchema (tables + v2-v22 migrations) and DBService queries split by area (expenses, accounts, budgets, ...)
  screens/                  # UI screens (home, add expense/transfer, accounts, budgets, recurring, insights, backups, list)
  widgets/                  # Charts (pie, trends, cash flow, category trend), month selector
  utils/                    # DbConstants, category colors, currency format, logger
assets/                     # App assets (declared in pubspec)
android/                  # Platform target (Android only)
```

## Installing a CI build on a phone

The APK comes from the Actions run as a **zip** — extract it and install the
`.apk` inside; installing the zip itself fails with "App not installed".

Three things get in the way of a sideloaded build, none of them a fault in
the APK:

- **Play Protect blocks it.** The app declares `READ_SMS` and `RECEIVE_SMS`,
  which on a finance app is the profile of banking malware, so Play Protect
  refuses it on sight ("App blocked to protect your device"). Turn the scan
  off while installing: Play Store → profile picture → Play Protect → gear →
  *Scan apps with Play Protect*, then turn it back on afterwards.
- **SMS permission cannot be granted.** SMS is a *restricted* permission:
  only the installer can release it, and a file manager does not. The app's
  permission screen then shows "Allow" greyed out. Tap the greyed-out
  "Allow" once so Android shows its "Restricted setting" notice, then go to
  App info → ⋮ → *Allow restricted settings* (the entry only appears after
  that notice) and set the permission; otherwise install over USB with
  `adb install -g app-arm64-v8a-release.apk`, which grants restricted
  permissions at install time. Everything except SMS import works without it.
- **The signature must match.** An APK signed with a different key than the
  installed copy is refused. CI signs with the release key from the
  repository secrets; without them a hand-started branch build mints a
  throwaway key per run, which can be installed only after uninstalling the
  existing app (see `docs/SIGNING.md`).

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
- App lock: toggle "App lock" under More → Settings → Security, next to its auto-lock timer (persists `biometricEnabled` in SharedPreferences); falls back to device PIN and shows a retry lock screen instead of exiting on failure.
- Backups to Drive: create OAuth credentials and configure the consent screen before shipping; current packages are present but require proper credentials.
- Budgets: budgets are month- and category-scoped; adjust DB versioning if schema changes further.
- Version: shown at the foot of the More tab and under Settings > About (tap to copy). Read from the installed package via `package_info_plus`, so it is correct for any build; CI additionally injects the commit SHA via `--dart-define`, which is appended only when known.
- Release signing: CI signs with a key from repository secrets (`ANDROID_KEYSTORE_BASE64` and friends); see `docs/SIGNING.md` for setup and for retiring the key that used to be committed.
- SMS import: needs the `READ_SMS` runtime permission, granted on first use of **More > Import from SMS**. Messages are parsed entirely on-device and never leave it.

  Declaring `READ_SMS` makes the app ineligible for Play Store distribution — store policy restricts that permission to apps whose core function is SMS handling. This build is signed and sideloaded (see the release-signing note above), so that is a deliberate trade rather than an oversight. Removing the permission from `AndroidManifest.xml` and the `another_telephony` dependency from `pubspec.yaml` reverts it; the rest of the app is unaffected.

  Parsing quality depends on templates banks change without notice, which is why nothing auto-posts. `lib/services/sms_import.dart` holds the patterns and is pure Dart — add a bank's wording there and cover it in `test/sms_import_test.dart`. Accuracy against the current formats is pinned down by those tests; the plugin layer in `lib/services/sms_service.dart` is thin and can only be verified on a real device.

  The default scan runs from a day before the last time the review queue was left empty (`SmsService.scanStartSince`): at least `SmsService.defaultWindow` (2 days) and at most `SmsService.maxCatchUp` (30 days). The first run therefore doesn't dump months of history into the queue, and a week between visits no longer loses the week's alerts. The mark only moves forward when every message found was imported or dismissed, so leaving some for later keeps them in the next scan. The scan-range menu still offers fixed spans and a custom range.

  The toggle gates both the permission request and the inbox read, so the app cannot touch SMS while it is off. Turning it off does not delete anything already imported.

  Account routing needs each account's last four digits filled in (Accounts > tap an account > *Last 4 digits*). Without them a parsed message still imports, but with no account attached, so it will not move any balance.
