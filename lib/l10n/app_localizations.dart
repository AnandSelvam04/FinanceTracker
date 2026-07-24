import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/date_format.dart';

/// Lightweight, hand-written localization (no codegen). The app is
/// translation-ready: add a locale by adding its map to [_values] and its
/// [Locale] to [supportedLocales]. Strings are exposed as getters so a typo is
/// a compile error rather than a silent runtime fallback. Any key missing from
/// a locale falls back to English.
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  /// Resolves localizations without a [BuildContext], e.g. for notification
  /// text produced by background services. Uses the device locale, falling
  /// back to English when it isn't supported.
  static AppLocalizations resolve([Locale? locale]) {
    final l = locale ?? ui.PlatformDispatcher.instance.locale;
    return AppLocalizations(
        _values.containsKey(l.languageCode) ? Locale(l.languageCode) : const Locale('en'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [Locale('en'), Locale('ta')];

  static const Map<String, Map<String, String>> _values = {
    'en': {
      // Navigation & chrome
      'appTitle': 'Finance Tracker',
      'howToUse': 'How to use',
      'navHome': 'Home',
      'navExpenses': 'Expenses',
      'navMore': 'More',
      'addTransaction': 'Add transaction',
      'addExpense': 'Add Expense',
      'addInvestment': 'Add Investment',
      'dashboardCharts': 'Dashboard & Charts',
      // More tab
      'accounts': 'Accounts',
      'monthlySummary': 'Monthly Summary',
      'cashFlow': 'Cash Flow',
      'categoryTrends': 'Category Trends',
      'investments': 'Investments',
      'recurring': 'Recurring',
      'budgets': 'Budgets',
      'backupExport': 'Backup & Export',
      'settings': 'Settings',
      'appLock': 'App lock',
      'appLockSubtitle': 'Require biometrics or device PIN on launch',
      // Shared actions & fields
      'cancel': 'Cancel',
      'save': 'Save',
      'add': 'Add',
      'delete': 'Delete',
      'category': 'Category',
      'amount': 'Amount',
      'year': 'Year',
      'month': 'Month',
      'none': 'None',
      // Settings
      'sectionGeneral': 'General',
      'sectionSecurity': 'Security',
      'currencySymbol': 'Currency symbol',
      'theme': 'Theme',
      'themeLight': 'Light',
      'themeDark': 'Dark',
      'themeSystem': 'System default',
      'defaultAccount': 'Default account',
      'defaultAccountSubtitle': 'Preselected for new transactions',
      'budgetBillAlerts': 'Budget & bill alerts',
      'budgetBillAlertsSubtitle':
          'Show dashboard warnings for budgets and due bills',
      'pushNotifications': 'Push notifications',
      'pushNotificationsSubtitle':
          'Reminders before bills are due and budget-limit alerts',
      'autoLock': 'Auto-lock',
      'autoLockSubtitle': 'When app lock is on, re-lock after being away',
      'encryptDatabase': 'Encrypt database',
      'encryptDatabaseSubtitle':
          'Protect on-device data with a device-secured key',
      'encrypting': 'Encrypting database…',
      'decrypting': 'Removing encryption…',
      'encryptionEnabled': 'Database encrypted',
      'encryptionDisabled': 'Database encryption removed',
      // Accounts
      'addAccount': 'Add Account',
      'editAccount': 'Edit Account',
      'accountName': 'Name',
      'accountType': 'Type',
      'currency': 'Currency',
      'exchangeRate': 'Exchange rate',
      'openingBalance': 'Opening Balance',
      'totalBalance': 'Total Balance',
      'transferBetweenAccounts': 'Transfer between accounts',
      'deleteAccount': 'Delete account',
      'noAccounts':
          'No accounts yet. Add cash, bank, UPI, or card accounts to track balances.',
      // Budgets
      'addBudget': 'Add Budget',
      'editBudget': 'Edit Budget',
      'budgetLabel': 'Budget',
      'spentLabel': 'Spent',
      'editBudgetTooltip': 'Edit budget',
      'deleteBudgetTooltip': 'Delete budget',
      'noBudgets': 'No budgets yet. Add one to start tracking.',
      // Add expense / income
      'addIncome': 'Add Income',
      'income': 'Income',
      'expense': 'Expense',
      'description': 'Description',
      'date': 'Date',
      'selectDate': 'Select Date',
      'source': 'Source',
      'account': 'Account',
      'paymentMode': 'Payment Mode',
      'saveAsTemplate': 'Save as quick-add template',
      'incomeAdded': 'Income added',
      'expenseAdded': 'Expense added',
      // Add investment
      'investmentAdded': 'Investment added',
      // Transfer
      'needTwoAccounts':
          'You need at least two accounts to record a transfer.',
      'fromAccount': 'From account',
      'toAccount': 'To account',
      'noteOptional': 'Note (optional)',
      'recordTransfer': 'Record Transfer',
      'transferRecorded': 'Transfer recorded',
      'amountReceived': 'Amount received',
      'selectAccount': 'Select an account',
      'mustDifferFromSource': 'Must differ from source account',
      'enterAmount': 'Enter an amount',
      'enterValidAmount': 'Enter a valid amount',
      // Dashboard
      'viewLabel': 'View',
      'noExpensesMonth': 'No expenses this month.',
      'noExpensesYear': 'No expenses this year.',
      'total': 'Total',
      'yearTotal': 'Year Total',
      'categoryBreakdownYear': 'Category Breakdown (Year)',
      'trendsLast12Months': 'Trends (Last 12 Months)',
      'quickAdd': 'Quick add',
      'postedRecurringOne': '1 recurring transaction posted',
      'postedRecurringMany': '{n} recurring transactions posted',
      'addedTemplate': 'Added {name}',
      'undo': 'Undo',
      // Net worth card
      'netWorth': 'Net Worth',
      'noHistoryYet': 'No history yet',
      'netWorthTrendSemantics': 'Net worth trend over the last 12 months',
      // Transactions list
      'transactions': 'Transactions',
      'filters': 'Filters',
      'downloadFilteredCsv': 'Download filtered (CSV)',
      'searchExpenses': 'Search Expenses',
      'all': 'All',
      'transfers': 'Transfers',
      'transfer': 'Transfer',
      'deleteExpenseTitle': 'Delete expense?',
      'deleteExpenseBody': 'Remove "{desc}" for {amount}?',
      'editExpense': 'Edit Expense',
      'editTransfer': 'Edit Transfer',
      'change': 'Change',
      'note': 'Note',
      'any': 'Any',
      'minAmount': 'Min amount',
      'maxAmount': 'Max amount',
      'dateRangeUsesYearMonth': 'Date range: uses Year/Month above',
      'dateRangeIs': 'Date range: {range}',
      'pick': 'Pick',
      'clear': 'Clear',
      'resetAll': 'Reset all',
      'apply': 'Apply',
      'nothingToDownload': 'Nothing to download for this filter.',
      'errorWithDetails': 'Error: {error}',
      'noExpensesFound': 'No expenses found.',
      // Lock screen
      'appLocked': 'Finance Tracker is locked',
      'unlock': 'Unlock',
      // Notifications
      'billDueSoon': 'Bill due soon',
      'billDueBody': '{desc} {amount} is due {when}',
      'dueToday': 'today',
      'dueTomorrow': 'tomorrow',
      'dueInDays': 'in {n} days',
      'overBudget': 'Over budget',
      'budgetWarning': 'Budget warning',
      'overBudgetBody': '{category}: over budget by {amount}',
      'budgetUsedBody': '{category}: {percent}% of budget used',
      // Weekday abbreviations (Mon..Sun) for date labels
      'weekdayMon': 'Mon',
      'weekdayTue': 'Tue',
      'weekdayWed': 'Wed',
      'weekdayThu': 'Thu',
      'weekdayFri': 'Fri',
      'weekdaySat': 'Sat',
      'weekdaySun': 'Sun',
      // Month names for date-group headers
      'monthJan': 'January',
      'monthFeb': 'February',
      'monthMar': 'March',
      'monthApr': 'April',
      'monthMay': 'May',
      'monthJun': 'June',
      'monthJul': 'July',
      'monthAug': 'August',
      'monthSep': 'September',
      'monthOct': 'October',
      'monthNov': 'November',
      'monthDec': 'December',
      // Recurring
      'addRecurring': 'Add Recurring',
      'editRecurring': 'Edit Recurring',
      'frequency': 'Frequency',
      'freqDaily': 'Daily',
      'freqWeekly': 'Weekly',
      'freqMonthly': 'Monthly',
      'freqYearly': 'Yearly',
      'nextDue': 'Next due',
      'nextShort': 'next',
      'fieldRequired': 'Required',
      'invalidValue': 'Invalid',
      'noRecurring':
          'No recurring transactions. Add rent, salary, bills, and they post automatically.',
      'deleteRule': 'Delete rule',
      'addRecurringRule': 'Add recurring rule',
      // Investments
      'totalInvested': 'Total Invested',
      'noInvestments': 'No investments yet. Add one to start tracking.',
      'contributionOne': '1 contribution',
      'contributionMany': '{n} contributions',
      'latest': 'latest',
      'totalInType': 'Total in {type}',
      'addToType': 'Add to {type}',
      'deleteContribution': 'Delete contribution?',
      'deleteContributionBody': 'Remove "{name}" for {amount}?',
      'editInvestment': 'Edit Investment',
      'enterInvestmentType': 'Enter investment type',
      'enterTypeOrPick': 'Enter a type or pick one above',
      'optional': 'optional',
      // Backups & export
      'backupRestore': 'Backup & Restore',
      'backupToDriveBtn': 'Backup to Google Drive',
      'restoreFromDriveBtn': 'Restore from Google Drive',
      'backupLocalJson': 'Backup locally (JSON)',
      'restoreLocalJson': 'Restore from local JSON',
      'driveSetupNote':
          'Google Drive requires a one-time sign-in setup in the build. If it fails, your data is still safe in local backups below.',
      'encryptedBackup': 'Encrypted backup',
      'encryptedBackupNote':
          'Protect an exported backup with a passphrase (AES-256). Keep the passphrase safe — it is required to restore and cannot be reset.',
      'encryptedBackupJson': 'Encrypted backup (JSON)',
      'restoreEncryptedBackup': 'Restore encrypted backup',
      'downloadEncryptedBackup': 'Download encrypted backup',
      'downloadShare': 'Download & Share',
      'downloadShareNote':
          'Save your data to Files/Downloads, email it, or send it to another app.',
      'downloadExpensesCsv': 'Download expenses (CSV)',
      'downloadInvestmentsCsv': 'Download investments (CSV)',
      'downloadFullJson': 'Download full data (JSON)',
      'importFromCsv': 'Import from CSV',
      'replaceAllTitle': 'Replace all data?',
      'replaceAllBody':
          'Restoring will delete everything currently in the app and replace it with the backup. This cannot be undone.',
      'replace': 'Replace',
      'newerBackupTitle': 'Warning: Newer Backup Found',
      'newerBackupBody':
          'A newer backup exists on Google Drive. Overwriting it may cause data loss from other devices.\n\nDo you want to continue and overwrite the remote backup?',
      'overwrite': 'Overwrite',
      'exported': 'Exported',
      'passphrase': 'Passphrase',
      'confirmPassphrase': 'Confirm passphrase',
      'passphraseMin': 'Use at least 4 characters',
      'passphraseMismatch': 'Passphrases do not match',
      'passphraseForgotWarning':
          'If you forget this passphrase, the backup cannot be recovered.',
      'encryptBackupTitle': 'Encrypt backup',
      'encrypt': 'Encrypt',
      'restoreAction': 'Restore',
      'noBackupYet': 'No backup yet — back up to avoid losing your data.',
      'justNow': 'just now',
      'lastBackup': 'Last backup: {ago}',
      'dayAgoOne': '{n} day ago',
      'dayAgoMany': '{n} days ago',
      'hourAgoOne': '{n} hour ago',
      'hourAgoMany': '{n} hours ago',
      'backedUpToDrive': 'Backed up to Drive',
      'restoredFromDrive': 'Restored from Drive',
      'localJsonCreated': 'Local JSON backup created',
      'restoredLocalJson': 'Restored from local JSON',
      'encryptedBackupCreated': 'Encrypted backup created',
      'restoredEncrypted': 'Restored from encrypted backup',
      'subjectEncrypted': 'Finance Tracker — Encrypted Backup',
      'subjectExpenses': 'Finance Tracker — Expenses',
      'subjectInvestments': 'Finance Tracker — Investments',
      'subjectFullBackup': 'Finance Tracker — Full Backup',
      // CSV import
      'columnN': 'Column {n}',
      'noValidRows': 'No valid rows to import.',
      'importedSkipped': 'Imported {imported}, skipped {skipped}',
      'pickCsvHint':
          'Pick a CSV file (e.g. a bank statement or an export from another app), then map its columns.',
      'chooseCsvFile': 'Choose CSV file',
      'firstRowHeader': 'First row is a header',
      'dateColumn': 'Date column',
      'descriptionColumn': 'Description column',
      'amountColumn': 'Amount column',
      'categoryColumnOptional': 'Category column (optional)',
      'typeColumnOptional': 'Type column (optional)',
      'importAllRowsAs': 'Import all rows as',
      'preview': 'Preview',
      'importAction': 'Import',
      'chooseDifferentFile': 'Choose a different file',
      'noValidRowsMapping': 'No valid rows with the current mapping.',
      'noDescription': '(no description)',
      'willImportSkip': 'Will import {n}, skip {skip}.',
      // Monthly summary
      'noTransactionsToInclude': 'No transactions to include.',
      'statementTitle': 'Finance Tracker Statement',
      'statementSubject': 'Statement {period}',
      'sharePdfStatement': 'Share PDF statement',
      'net': 'Net',
      'savingsRate': 'Savings rate',
      'expenseVsLastMonth': 'Expense vs last month: ',
      'topCategories': 'Top Categories',
      // Category trends
      'noExpenses12Months': 'No expenses in the last 12 months.',
      'spendingByCategory': 'Spending by Category (Last 12 Months)',
      // Cash flow
      'incomeVsExpense12': 'Income vs Expense (Last 12 Months)',
      'totalIncome': 'Total Income',
      'totalExpense': 'Total Expense',
      // Accounts
      'deleteAccountTitle': 'Delete account?',
      'deleteAccountBody':
          'Remove "{name}"? Transactions linked to it are kept but lose their account link.',
      // Add expense
      'failedToSave': 'Failed to save: {error}',
      // Tutorial / how to use
      'tutStep1Title': 'Add your first entries',
      'tutStep1Body':
          'Use Add Expense or Add Investment to record transactions with amount, date, and category/type.',
      'tutStep2Title': 'See monthly or yearly totals',
      'tutStep2Body':
          'On Home, switch Month/Year to view charts, totals, and category breakdowns.',
      'tutStep3Title': 'Back up before switching devices',
      'tutStep3Body':
          'Open Backups to save to Google Drive (appData) or create a local JSON/CSV export.',
      'tutStep4Title': 'Restore anytime',
      'tutStep4Body':
          'Use Restore from Drive or local JSON to bring data back after reinstall or on a new phone.',
      'tutStep5Title': 'Set budgets and track spending',
      'tutStep5Body':
          'Add monthly budgets per category in the Budgets tab to monitor progress and avoid overspending.',
      'tutStep6Title': 'Optional app lock',
      'tutStep6Body':
          'Enable "App lock" in the More tab to require biometrics or your device PIN on launch.',
      // Widgets
      'previousMonth': 'Previous month',
      'nextMonth': 'Next month',
      'selectCategoriesToCompare': 'Select categories to compare.',
      'noTransactions12Months': 'No transactions in the last 12 months.',
      'alertsTitle': 'Alerts',
      'billOverdue': 'overdue',
      'billDueToday': 'due today',
      'billDueTomorrow': 'due tomorrow',
      'billDueInDaysN': 'due in {n} days',
      // Payment modes (display only; stored values stay English)
      'pmCash': 'Cash',
      'pmCreditCard': 'Credit Card',
      'pmDebitCard': 'Debit Card',
      'pmUpi': 'UPI',
      'pmOther': 'Other',
    },
    'ta': {
      'appTitle': 'Finance Tracker',
      'howToUse': 'எப்படி பயன்படுத்துவது',
      'navHome': 'முகப்பு',
      'navExpenses': 'செலவுகள்',
      'navMore': 'மேலும்',
      'addTransaction': 'பரிவர்த்தனை சேர்',
      'addExpense': 'செலவு சேர்',
      'addInvestment': 'முதலீடு சேர்',
      'dashboardCharts': 'டாஷ்போர்டு & விளக்கப்படங்கள்',
      'accounts': 'கணக்குகள்',
      'monthlySummary': 'மாதாந்திர சுருக்கம்',
      'cashFlow': 'பணப் புழக்கம்',
      'categoryTrends': 'வகை போக்குகள்',
      'investments': 'முதலீடுகள்',
      'recurring': 'தொடர்ச்சியான',
      'budgets': 'பட்ஜெட்டுகள்',
      'backupExport': 'காப்புப்பிரதி & ஏற்றுமதி',
      'settings': 'அமைப்புகள்',
      'appLock': 'ஆப் பூட்டு',
      'appLockSubtitle': 'தொடங்கும்போது பயோமெட்ரிக்ஸ் அல்லது சாதன பின் தேவை',
      'cancel': 'ரத்து செய்',
      'save': 'சேமி',
      'add': 'சேர்',
      'delete': 'நீக்கு',
      'category': 'பிரிவு',
      'amount': 'தொகை',
      'year': 'ஆண்டு',
      'month': 'மாதம்',
      'none': 'எதுவுமில்லை',
      'sectionGeneral': 'பொது',
      'sectionSecurity': 'பாதுகாப்பு',
      'currencySymbol': 'நாணய சின்னம்',
      'theme': 'தீம்',
      'themeLight': 'ஒளி',
      'themeDark': 'இருள்',
      'themeSystem': 'சிஸ்டம் இயல்புநிலை',
      'defaultAccount': 'இயல்புநிலை கணக்கு',
      'defaultAccountSubtitle': 'புதிய பரிவர்த்தனைகளுக்கு முன்தேர்ந்தெடுக்கப்பட்டது',
      'budgetBillAlerts': 'பட்ஜெட் & பில் எச்சரிக்கைகள்',
      'budgetBillAlertsSubtitle':
          'பட்ஜெட்டுகள் மற்றும் செலுத்த வேண்டிய பில்களுக்கான டாஷ்போர்டு எச்சரிக்கைகளைக் காட்டு',
      'pushNotifications': 'புஷ் அறிவிப்புகள்',
      'pushNotificationsSubtitle':
          'பில்கள் செலுத்த வேண்டிய நாளுக்கு முன் நினைவூட்டல்கள் மற்றும் பட்ஜெட் வரம்பு எச்சரிக்கைகள்',
      'autoLock': 'தானியங்கி பூட்டு',
      'autoLockSubtitle':
          'ஆப் பூட்டு இயக்கத்தில் இருக்கும்போது, விலகியிருந்த பிறகு மீண்டும் பூட்டு',
      'encryptDatabase': 'தரவுத்தளத்தை குறியாக்கு',
      'encryptDatabaseSubtitle':
          'சாதனத்தால் பாதுகாக்கப்பட்ட விசையுடன் சாதனத் தரவைப் பாதுகாக்கவும்',
      'encrypting': 'தரவுத்தளம் குறியாக்கப்படுகிறது…',
      'decrypting': 'குறியாக்கம் அகற்றப்படுகிறது…',
      'encryptionEnabled': 'தரவுத்தளம் குறியாக்கப்பட்டது',
      'encryptionDisabled': 'தரவுத்தள குறியாக்கம் அகற்றப்பட்டது',
      'addAccount': 'கணக்கு சேர்',
      'editAccount': 'கணக்கைத் திருத்து',
      'accountName': 'பெயர்',
      'accountType': 'வகை',
      'currency': 'நாணயம்',
      'exchangeRate': 'மாற்று விகிதம்',
      'openingBalance': 'தொடக்க இருப்பு',
      'totalBalance': 'மொத்த இருப்பு',
      'transferBetweenAccounts': 'கணக்குகளுக்கிடையே பரிமாற்றம்',
      'deleteAccount': 'கணக்கை நீக்கு',
      'noAccounts':
          'இன்னும் கணக்குகள் இல்லை. இருப்பைக் கண்காணிக்க பணம், வங்கி, UPI அல்லது கார்டு கணக்குகளைச் சேர்க்கவும்.',
      'addBudget': 'பட்ஜெட் சேர்',
      'editBudget': 'பட்ஜெட்டைத் திருத்து',
      'budgetLabel': 'பட்ஜெட்',
      'spentLabel': 'செலவழித்தது',
      'editBudgetTooltip': 'பட்ஜெட்டைத் திருத்து',
      'deleteBudgetTooltip': 'பட்ஜெட்டை நீக்கு',
      'noBudgets': 'இன்னும் பட்ஜெட்டுகள் இல்லை. கண்காணிக்கத் தொடங்க ஒன்றைச் சேர்க்கவும்.',
      'addIncome': 'வருமானம் சேர்',
      'income': 'வருமானம்',
      'expense': 'செலவு',
      'description': 'விவரம்',
      'date': 'தேதி',
      'selectDate': 'தேதி தேர்ந்தெடு',
      'source': 'மூலம்',
      'account': 'கணக்கு',
      'paymentMode': 'பணம் செலுத்தும் முறை',
      'saveAsTemplate': 'விரைவு-சேர் டெம்ப்ளேட்டாக சேமி',
      'incomeAdded': 'வருமானம் சேர்க்கப்பட்டது',
      'expenseAdded': 'செலவு சேர்க்கப்பட்டது',
      'investmentAdded': 'முதலீடு சேர்க்கப்பட்டது',
      'needTwoAccounts':
          'பரிமாற்றத்தைப் பதிவு செய்ய குறைந்தது இரண்டு கணக்குகள் தேவை.',
      'fromAccount': 'அனுப்பும் கணக்கு',
      'toAccount': 'பெறும் கணக்கு',
      'noteOptional': 'குறிப்பு (விருப்பம்)',
      'recordTransfer': 'பரிமாற்றத்தைப் பதிவு செய்',
      'transferRecorded': 'பரிமாற்றம் பதிவு செய்யப்பட்டது',
      'amountReceived': 'பெறப்பட்ட தொகை',
      'selectAccount': 'ஒரு கணக்கைத் தேர்ந்தெடுக்கவும்',
      'mustDifferFromSource': 'அனுப்பும் கணக்கிலிருந்து வேறுபட வேண்டும்',
      'enterAmount': 'தொகையை உள்ளிடவும்',
      'enterValidAmount': 'சரியான தொகையை உள்ளிடவும்',
      'viewLabel': 'காட்சி',
      'noExpensesMonth': 'இந்த மாதம் செலவுகள் இல்லை.',
      'noExpensesYear': 'இந்த ஆண்டு செலவுகள் இல்லை.',
      'total': 'மொத்தம்',
      'yearTotal': 'ஆண்டு மொத்தம்',
      'categoryBreakdownYear': 'வகை விவரம் (ஆண்டு)',
      'trendsLast12Months': 'போக்குகள் (கடந்த 12 மாதங்கள்)',
      'quickAdd': 'விரைவு சேர்',
      'postedRecurringOne': '1 தொடர் பரிவர்த்தனை பதிவு செய்யப்பட்டது',
      'postedRecurringMany': '{n} தொடர் பரிவர்த்தனைகள் பதிவு செய்யப்பட்டன',
      'addedTemplate': '{name} சேர்க்கப்பட்டது',
      'undo': 'செயல்தவிர்',
      'netWorth': 'நிகர மதிப்பு',
      'noHistoryYet': 'இன்னும் வரலாறு இல்லை',
      'netWorthTrendSemantics': 'கடந்த 12 மாதங்களின் நிகர மதிப்பு போக்கு',
      'transactions': 'பரிவர்த்தனைகள்',
      'filters': 'வடிப்பான்கள்',
      'downloadFilteredCsv': 'வடிகட்டியதைப் பதிவிறக்கு (CSV)',
      'searchExpenses': 'செலவுகளைத் தேடு',
      'all': 'அனைத்தும்',
      'transfers': 'பரிமாற்றங்கள்',
      'transfer': 'பரிமாற்றம்',
      'deleteExpenseTitle': 'செலவை நீக்கவா?',
      'deleteExpenseBody': '"{desc}" ({amount}) நீக்கவா?',
      'editExpense': 'செலவைத் திருத்து',
      'editTransfer': 'பரிமாற்றத்தைத் திருத்து',
      'change': 'மாற்று',
      'note': 'குறிப்பு',
      'any': 'ஏதேனும்',
      'minAmount': 'குறைந்தபட்ச தொகை',
      'maxAmount': 'அதிகபட்ச தொகை',
      'dateRangeUsesYearMonth': 'தேதி வரம்பு: மேலே உள்ள ஆண்டு/மாதம் பயன்படும்',
      'dateRangeIs': 'தேதி வரம்பு: {range}',
      'pick': 'தேர்வு',
      'clear': 'அழி',
      'resetAll': 'அனைத்தையும் மீட்டமை',
      'apply': 'பயன்படுத்து',
      'nothingToDownload': 'இந்த வடிப்பானுக்கு பதிவிறக்க எதுவும் இல்லை.',
      'errorWithDetails': 'பிழை: {error}',
      'noExpensesFound': 'செலவுகள் எதுவும் கிடைக்கவில்லை.',
      'appLocked': 'Finance Tracker பூட்டப்பட்டுள்ளது',
      'unlock': 'திற',
      'billDueSoon': 'பில் விரைவில் செலுத்த வேண்டும்',
      'billDueBody': '{desc} {amount} {when} செலுத்த வேண்டும்',
      'dueToday': 'இன்று',
      'dueTomorrow': 'நாளை',
      'dueInDays': '{n} நாட்களில்',
      'overBudget': 'பட்ஜெட்டை மீறியது',
      'budgetWarning': 'பட்ஜெட் எச்சரிக்கை',
      'overBudgetBody': '{category}: பட்ஜெட்டை விட {amount} அதிகம்',
      'budgetUsedBody': '{category}: பட்ஜெட்டில் {percent}% பயன்படுத்தப்பட்டது',
      // Weekday abbreviations (Mon..Sun)
      'weekdayMon': 'திங்',
      'weekdayTue': 'செவ்',
      'weekdayWed': 'புத',
      'weekdayThu': 'வியா',
      'weekdayFri': 'வெள்',
      'weekdaySat': 'சனி',
      'weekdaySun': 'ஞாயி',
      // Month names
      'monthJan': 'ஜனவரி',
      'monthFeb': 'பிப்ரவரி',
      'monthMar': 'மார்ச்',
      'monthApr': 'ஏப்ரல்',
      'monthMay': 'மே',
      'monthJun': 'ஜூன்',
      'monthJul': 'ஜூலை',
      'monthAug': 'ஆகஸ்ட்',
      'monthSep': 'செப்டம்பர்',
      'monthOct': 'அக்டோபர்',
      'monthNov': 'நவம்பர்',
      'monthDec': 'டிசம்பர்',
      // Recurring
      'addRecurring': 'தொடர் பரிவர்த்தனை சேர்',
      'editRecurring': 'தொடர் பரிவர்த்தனையைத் திருத்து',
      'frequency': 'அதிர்வெண்',
      'freqDaily': 'தினசரி',
      'freqWeekly': 'வாராந்திரம்',
      'freqMonthly': 'மாதாந்திரம்',
      'freqYearly': 'ஆண்டுதோறும்',
      'nextDue': 'அடுத்த தேதி',
      'nextShort': 'அடுத்து',
      'fieldRequired': 'தேவை',
      'invalidValue': 'தவறானது',
      'noRecurring':
          'தொடர் பரிவர்த்தனைகள் இல்லை. வாடகை, சம்பளம், பில்களைச் சேர்த்தால் அவை தானாகவே பதிவாகும்.',
      'deleteRule': 'விதியை நீக்கு',
      'addRecurringRule': 'தொடர் விதி சேர்',
      // Investments
      'totalInvested': 'மொத்த முதலீடு',
      'noInvestments': 'இன்னும் முதலீடுகள் இல்லை. கண்காணிக்கத் தொடங்க ஒன்றைச் சேர்க்கவும்.',
      'contributionOne': '1 பங்களிப்பு',
      'contributionMany': '{n} பங்களிப்புகள்',
      'latest': 'சமீபத்தியது',
      'totalInType': '{type} இல் மொத்தம்',
      'addToType': '{type} இல் சேர்',
      'deleteContribution': 'பங்களிப்பை நீக்கவா?',
      'deleteContributionBody': '"{name}" ({amount}) நீக்கவா?',
      'editInvestment': 'முதலீட்டைத் திருத்து',
      'enterInvestmentType': 'முதலீட்டு வகையை உள்ளிடவும்',
      'enterTypeOrPick': 'ஒரு வகையை உள்ளிடவும் அல்லது மேலே தேர்ந்தெடுக்கவும்',
      'optional': 'விருப்பம்',
      // Backups & export
      'backupRestore': 'காப்புப்பிரதி & மீட்டமை',
      'backupToDriveBtn': 'Google Drive இல் காப்புப்பிரதி',
      'restoreFromDriveBtn': 'Google Drive இலிருந்து மீட்டமை',
      'backupLocalJson': 'சாதனத்தில் காப்புப்பிரதி (JSON)',
      'restoreLocalJson': 'உள்ளூர் JSON இலிருந்து மீட்டமை',
      'driveSetupNote':
          'Google Drive க்கு பதிப்பில் ஒரு முறை உள்நுழைவு அமைப்பு தேவை. அது தோல்வியடைந்தாலும், உங்கள் தரவு கீழே உள்ள உள்ளூர் காப்புப்பிரதிகளில் பாதுகாப்பாக இருக்கும்.',
      'encryptedBackup': 'குறியாக்கப்பட்ட காப்புப்பிரதி',
      'encryptedBackupNote':
          'ஏற்றுமதி செய்யப்பட்ட காப்புப்பிரதியை கடவுச்சொல்லுடன் பாதுகாக்கவும் (AES-256). கடவுச்சொல்லைப் பாதுகாப்பாக வைக்கவும் — மீட்டமைக்க இது தேவை, மீட்டமைக்க முடியாது.',
      'encryptedBackupJson': 'குறியாக்கப்பட்ட காப்புப்பிரதி (JSON)',
      'restoreEncryptedBackup': 'குறியாக்கப்பட்ட காப்புப்பிரதியை மீட்டமை',
      'downloadEncryptedBackup': 'குறியாக்கப்பட்ட காப்புப்பிரதியைப் பதிவிறக்கு',
      'downloadShare': 'பதிவிறக்கு & பகிர்',
      'downloadShareNote':
          'உங்கள் தரவை Files/Downloads இல் சேமிக்கவும், மின்னஞ்சல் அனுப்பவும் அல்லது வேறு ஆப்புக்கு அனுப்பவும்.',
      'downloadExpensesCsv': 'செலவுகளைப் பதிவிறக்கு (CSV)',
      'downloadInvestmentsCsv': 'முதலீடுகளைப் பதிவிறக்கு (CSV)',
      'downloadFullJson': 'முழு தரவைப் பதிவிறக்கு (JSON)',
      'importFromCsv': 'CSV இலிருந்து இறக்குமதி',
      'replaceAllTitle': 'அனைத்து தரவையும் மாற்றவா?',
      'replaceAllBody':
          'மீட்டமைப்பது ஆப்பில் தற்போது உள்ள அனைத்தையும் நீக்கி காப்புப்பிரதியுடன் மாற்றும். இதை மீட்டமைக்க முடியாது.',
      'replace': 'மாற்று',
      'newerBackupTitle': 'எச்சரிக்கை: புதிய காப்புப்பிரதி கண்டறியப்பட்டது',
      'newerBackupBody':
          'Google Drive இல் புதிய காப்புப்பிரதி உள்ளது. அதை மேலெழுதுவது மற்ற சாதனங்களிலிருந்து தரவு இழப்பை ஏற்படுத்தலாம்.\n\nதொடர்ந்து தொலைநிலை காப்புப்பிரதியை மேலெழுத விரும்புகிறீர்களா?',
      'overwrite': 'மேலெழுது',
      'exported': 'ஏற்றுமதி செய்யப்பட்டது',
      'passphrase': 'கடவுச்சொல்',
      'confirmPassphrase': 'கடவுச்சொல்லை உறுதிப்படுத்து',
      'passphraseMin': 'குறைந்தது 4 எழுத்துகளைப் பயன்படுத்தவும்',
      'passphraseMismatch': 'கடவுச்சொற்கள் பொருந்தவில்லை',
      'passphraseForgotWarning':
          'இந்த கடவுச்சொல்லை மறந்தால், காப்புப்பிரதியை மீட்டெடுக்க முடியாது.',
      'encryptBackupTitle': 'காப்புப்பிரதியைக் குறியாக்கு',
      'encrypt': 'குறியாக்கு',
      'restoreAction': 'மீட்டமை',
      'noBackupYet': 'இன்னும் காப்புப்பிரதி இல்லை — தரவை இழக்காமல் இருக்க காப்புப்பிரதி எடுக்கவும்.',
      'justNow': 'இப்போது',
      'lastBackup': 'கடைசி காப்புப்பிரதி: {ago}',
      'dayAgoOne': '{n} நாள் முன்பு',
      'dayAgoMany': '{n} நாட்கள் முன்பு',
      'hourAgoOne': '{n} மணிநேரம் முன்பு',
      'hourAgoMany': '{n} மணிநேரம் முன்பு',
      'backedUpToDrive': 'Drive இல் காப்புப்பிரதி எடுக்கப்பட்டது',
      'restoredFromDrive': 'Drive இலிருந்து மீட்டமைக்கப்பட்டது',
      'localJsonCreated': 'உள்ளூர் JSON காப்புப்பிரதி உருவாக்கப்பட்டது',
      'restoredLocalJson': 'உள்ளூர் JSON இலிருந்து மீட்டமைக்கப்பட்டது',
      'encryptedBackupCreated': 'குறியாக்கப்பட்ட காப்புப்பிரதி உருவாக்கப்பட்டது',
      'restoredEncrypted': 'குறியாக்கப்பட்ட காப்புப்பிரதியிலிருந்து மீட்டமைக்கப்பட்டது',
      'subjectEncrypted': 'Finance Tracker — குறியாக்கப்பட்ட காப்புப்பிரதி',
      'subjectExpenses': 'Finance Tracker — செலவுகள்',
      'subjectInvestments': 'Finance Tracker — முதலீடுகள்',
      'subjectFullBackup': 'Finance Tracker — முழு காப்புப்பிரதி',
      // CSV import
      'columnN': 'நெடுவரிசை {n}',
      'noValidRows': 'இறக்குமதி செய்ய செல்லுபடியான வரிசைகள் இல்லை.',
      'importedSkipped': '{imported} இறக்குமதி, {skipped} தவிர்க்கப்பட்டது',
      'pickCsvHint':
          'ஒரு CSV கோப்பைத் தேர்ந்தெடுக்கவும் (எ.கா. வங்கி அறிக்கை அல்லது வேறு ஆப்பிலிருந்து ஏற்றுமதி), பின்னர் அதன் நெடுவரிசைகளை வரைபடமாக்கவும்.',
      'chooseCsvFile': 'CSV கோப்பைத் தேர்ந்தெடு',
      'firstRowHeader': 'முதல் வரிசை தலைப்பு',
      'dateColumn': 'தேதி நெடுவரிசை',
      'descriptionColumn': 'விவர நெடுவரிசை',
      'amountColumn': 'தொகை நெடுவரிசை',
      'categoryColumnOptional': 'பிரிவு நெடுவரிசை (விருப்பம்)',
      'typeColumnOptional': 'வகை நெடுவரிசை (விருப்பம்)',
      'importAllRowsAs': 'அனைத்து வரிசைகளையும் இவ்வாறு இறக்குமதி செய்',
      'preview': 'முன்னோட்டம்',
      'importAction': 'இறக்குமதி',
      'chooseDifferentFile': 'வேறு கோப்பைத் தேர்ந்தெடு',
      'noValidRowsMapping': 'தற்போதைய வரைபடத்துடன் செல்லுபடியான வரிசைகள் இல்லை.',
      'noDescription': '(விவரம் இல்லை)',
      'willImportSkip': '{n} இறக்குமதி செய்யும், {skip} தவிர்க்கும்.',
      // Monthly summary
      'noTransactionsToInclude': 'சேர்க்க பரிவர்த்தனைகள் இல்லை.',
      'statementTitle': 'Finance Tracker அறிக்கை',
      'statementSubject': 'அறிக்கை {period}',
      'sharePdfStatement': 'PDF அறிக்கையைப் பகிர்',
      'net': 'நிகரம்',
      'savingsRate': 'சேமிப்பு விகிதம்',
      'expenseVsLastMonth': 'சென்ற மாதத்துடன் ஒப்பிடும்போது செலவு: ',
      'topCategories': 'முதன்மை பிரிவுகள்',
      // Category trends
      'noExpenses12Months': 'கடந்த 12 மாதங்களில் செலவுகள் இல்லை.',
      'spendingByCategory': 'பிரிவு வாரியாக செலவு (கடந்த 12 மாதங்கள்)',
      // Cash flow
      'incomeVsExpense12': 'வருமானம் vs செலவு (கடந்த 12 மாதங்கள்)',
      'totalIncome': 'மொத்த வருமானம்',
      'totalExpense': 'மொத்த செலவு',
      // Accounts
      'deleteAccountTitle': 'கணக்கை நீக்கவா?',
      'deleteAccountBody':
          '"{name}" ஐ நீக்கவா? அதனுடன் இணைக்கப்பட்ட பரிவர்த்தனைகள் வைக்கப்படும் ஆனால் கணக்கு இணைப்பை இழக்கும்.',
      // Add expense
      'failedToSave': 'சேமிக்க முடியவில்லை: {error}',
      // Tutorial / how to use
      'tutStep1Title': 'உங்கள் முதல் பதிவுகளைச் சேர்க்கவும்',
      'tutStep1Body':
          'தொகை, தேதி மற்றும் பிரிவு/வகையுடன் பரிவர்த்தனைகளைப் பதிவு செய்ய செலவு சேர் அல்லது முதலீடு சேர் ஐப் பயன்படுத்தவும்.',
      'tutStep2Title': 'மாதாந்திர அல்லது ஆண்டு மொத்தங்களைப் பார்க்கவும்',
      'tutStep2Body':
          'முகப்பில், விளக்கப்படங்கள், மொத்தங்கள் மற்றும் பிரிவு விவரங்களைப் பார்க்க மாதம்/ஆண்டு ஐ மாற்றவும்.',
      'tutStep3Title': 'சாதனங்களை மாற்றும் முன் காப்புப்பிரதி எடுக்கவும்',
      'tutStep3Body':
          'Google Drive (appData) இல் சேமிக்க அல்லது உள்ளூர் JSON/CSV ஏற்றுமதியை உருவாக்க காப்புப்பிரதிகளைத் திறக்கவும்.',
      'tutStep4Title': 'எப்போது வேண்டுமானாலும் மீட்டமை',
      'tutStep4Body':
          'மீண்டும் நிறுவிய பிறகு அல்லது புதிய தொலைபேசியில் தரவை மீண்டும் கொண்டுவர Drive அல்லது உள்ளூர் JSON இலிருந்து மீட்டமை ஐப் பயன்படுத்தவும்.',
      'tutStep5Title': 'பட்ஜெட்டுகளை அமைத்து செலவைக் கண்காணிக்கவும்',
      'tutStep5Body':
          'முன்னேற்றத்தைக் கண்காணிக்க மற்றும் அதிகச் செலவைத் தவிர்க்க பட்ஜெட்டுகள் தாவலில் ஒவ்வொரு பிரிவுக்கும் மாதாந்திர பட்ஜெட்டுகளைச் சேர்க்கவும்.',
      'tutStep6Title': 'விருப்ப ஆப் பூட்டு',
      'tutStep6Body':
          'தொடங்கும்போது பயோமெட்ரிக்ஸ் அல்லது சாதன பின் தேவைப்பட மேலும் தாவலில் "ஆப் பூட்டு" ஐ இயக்கவும்.',
      // Widgets
      'previousMonth': 'முந்தைய மாதம்',
      'nextMonth': 'அடுத்த மாதம்',
      'selectCategoriesToCompare': 'ஒப்பிட பிரிவுகளைத் தேர்ந்தெடுக்கவும்.',
      'noTransactions12Months': 'கடந்த 12 மாதங்களில் பரிவர்த்தனைகள் இல்லை.',
      'alertsTitle': 'எச்சரிக்கைகள்',
      'billOverdue': 'தாமதம்',
      'billDueToday': 'இன்று செலுத்த வேண்டும்',
      'billDueTomorrow': 'நாளை செலுத்த வேண்டும்',
      'billDueInDaysN': '{n} நாட்களில் செலுத்த வேண்டும்',
      // Payment modes
      'pmCash': 'பணம்',
      'pmCreditCard': 'கிரெடிட் கார்டு',
      'pmDebitCard': 'டெபிட் கார்டு',
      'pmUpi': 'UPI',
      'pmOther': 'மற்றவை',
    },
  };

  String _t(String key) =>
      _values[locale.languageCode]?[key] ?? _values['en']![key] ?? key;

  /// Looks up [key] and substitutes `{name}` placeholders from [args].
  String _tArgs(String key, Map<String, String> args) {
    var out = _t(key);
    args.forEach((name, value) {
      out = out.replaceAll('{$name}', value);
    });
    return out;
  }

  // Navigation & chrome
  String get appTitle => _t('appTitle');
  String get howToUse => _t('howToUse');
  String get navHome => _t('navHome');
  String get navExpenses => _t('navExpenses');
  String get navMore => _t('navMore');
  String get addTransaction => _t('addTransaction');
  String get addExpense => _t('addExpense');
  String get addInvestment => _t('addInvestment');
  String get dashboardCharts => _t('dashboardCharts');
  String get accounts => _t('accounts');
  String get monthlySummary => _t('monthlySummary');
  String get cashFlow => _t('cashFlow');
  String get categoryTrends => _t('categoryTrends');
  String get investments => _t('investments');
  String get recurring => _t('recurring');
  String get budgets => _t('budgets');
  String get backupExport => _t('backupExport');
  String get settings => _t('settings');
  String get appLock => _t('appLock');
  String get appLockSubtitle => _t('appLockSubtitle');
  // Shared
  String get cancel => _t('cancel');
  String get save => _t('save');
  String get add => _t('add');
  String get delete => _t('delete');
  String get category => _t('category');
  String get amount => _t('amount');
  String get year => _t('year');
  String get month => _t('month');
  String get none => _t('none');
  // Settings
  String get sectionGeneral => _t('sectionGeneral');
  String get sectionSecurity => _t('sectionSecurity');
  String get currencySymbol => _t('currencySymbol');
  String get theme => _t('theme');
  String get themeLight => _t('themeLight');
  String get themeDark => _t('themeDark');
  String get themeSystem => _t('themeSystem');
  String get defaultAccount => _t('defaultAccount');
  String get defaultAccountSubtitle => _t('defaultAccountSubtitle');
  String get budgetBillAlerts => _t('budgetBillAlerts');
  String get budgetBillAlertsSubtitle => _t('budgetBillAlertsSubtitle');
  String get pushNotifications => _t('pushNotifications');
  String get pushNotificationsSubtitle => _t('pushNotificationsSubtitle');
  String get autoLock => _t('autoLock');
  String get autoLockSubtitle => _t('autoLockSubtitle');
  String get encryptDatabase => _t('encryptDatabase');
  String get encryptDatabaseSubtitle => _t('encryptDatabaseSubtitle');
  String get encrypting => _t('encrypting');
  String get decrypting => _t('decrypting');
  String get encryptionEnabled => _t('encryptionEnabled');
  String get encryptionDisabled => _t('encryptionDisabled');
  // Accounts
  String get addAccount => _t('addAccount');
  String get editAccount => _t('editAccount');
  String get accountName => _t('accountName');
  String get accountType => _t('accountType');
  String get currency => _t('currency');
  String get exchangeRate => _t('exchangeRate');
  String get openingBalance => _t('openingBalance');
  String get totalBalance => _t('totalBalance');
  String get transferBetweenAccounts => _t('transferBetweenAccounts');
  String get deleteAccount => _t('deleteAccount');
  String get noAccounts => _t('noAccounts');
  // Budgets
  String get addBudget => _t('addBudget');
  String get editBudget => _t('editBudget');
  String get budgetLabel => _t('budgetLabel');
  String get spentLabel => _t('spentLabel');
  String get editBudgetTooltip => _t('editBudgetTooltip');
  String get deleteBudgetTooltip => _t('deleteBudgetTooltip');
  String get noBudgets => _t('noBudgets');
  // Add expense / income
  String get addIncome => _t('addIncome');
  String get income => _t('income');
  String get expense => _t('expense');
  String get description => _t('description');
  String get date => _t('date');
  String get selectDate => _t('selectDate');
  String get source => _t('source');
  String get account => _t('account');
  String get paymentMode => _t('paymentMode');
  String get saveAsTemplate => _t('saveAsTemplate');
  String get incomeAdded => _t('incomeAdded');
  String get expenseAdded => _t('expenseAdded');
  // Add investment
  String get investmentAdded => _t('investmentAdded');
  // Transfer
  String get needTwoAccounts => _t('needTwoAccounts');
  String get fromAccount => _t('fromAccount');
  String get toAccount => _t('toAccount');
  String get noteOptional => _t('noteOptional');
  String get recordTransfer => _t('recordTransfer');
  String get transferRecorded => _t('transferRecorded');
  String get amountReceived => _t('amountReceived');
  String get selectAccount => _t('selectAccount');
  String get mustDifferFromSource => _t('mustDifferFromSource');
  String get enterAmount => _t('enterAmount');
  String get enterValidAmount => _t('enterValidAmount');
  // Dashboard
  String get viewLabel => _t('viewLabel');
  String get noExpensesMonth => _t('noExpensesMonth');
  String get noExpensesYear => _t('noExpensesYear');
  String get total => _t('total');
  String get yearTotal => _t('yearTotal');
  String get categoryBreakdownYear => _t('categoryBreakdownYear');
  String get trendsLast12Months => _t('trendsLast12Months');
  String get quickAdd => _t('quickAdd');
  String postedRecurring(int n) => n == 1
      ? _t('postedRecurringOne')
      : _tArgs('postedRecurringMany', {'n': '$n'});
  String addedTemplate(String name) => _tArgs('addedTemplate', {'name': name});
  String get undo => _t('undo');
  // Net worth card
  String get netWorth => _t('netWorth');
  String get noHistoryYet => _t('noHistoryYet');
  String get netWorthTrendSemantics => _t('netWorthTrendSemantics');
  // Transactions list
  String get transactions => _t('transactions');
  String get filters => _t('filters');
  String get downloadFilteredCsv => _t('downloadFilteredCsv');
  String get searchExpenses => _t('searchExpenses');
  String get all => _t('all');
  String get transfers => _t('transfers');
  String get transfer => _t('transfer');
  String get deleteExpenseTitle => _t('deleteExpenseTitle');
  String deleteExpenseBody(String desc, String amount) =>
      _tArgs('deleteExpenseBody', {'desc': desc, 'amount': amount});
  String get editExpense => _t('editExpense');
  String get editTransfer => _t('editTransfer');
  String get change => _t('change');
  String get note => _t('note');
  String get any => _t('any');
  String get minAmount => _t('minAmount');
  String get maxAmount => _t('maxAmount');
  String get dateRangeUsesYearMonth => _t('dateRangeUsesYearMonth');
  String dateRangeIs(String range) => _tArgs('dateRangeIs', {'range': range});
  String get pick => _t('pick');
  String get clear => _t('clear');
  String get resetAll => _t('resetAll');
  String get apply => _t('apply');
  String get nothingToDownload => _t('nothingToDownload');
  String errorWithDetails(String error) =>
      _tArgs('errorWithDetails', {'error': error});
  String get noExpensesFound => _t('noExpensesFound');
  // Lock screen
  String get appLocked => _t('appLocked');
  String get unlock => _t('unlock');
  // Notifications
  String get billDueSoon => _t('billDueSoon');
  String billDueBody(String desc, String amount, String when) =>
      _tArgs('billDueBody', {'desc': desc, 'amount': amount, 'when': when});
  String get dueToday => _t('dueToday');
  String get dueTomorrow => _t('dueTomorrow');
  String dueInDays(int n) => _tArgs('dueInDays', {'n': '$n'});
  String get overBudget => _t('overBudget');
  String get budgetWarning => _t('budgetWarning');
  String overBudgetBody(String category, String amount) =>
      _tArgs('overBudgetBody', {'category': category, 'amount': amount});
  String budgetUsedBody(String category, int percent) =>
      _tArgs('budgetUsedBody', {'category': category, 'percent': '$percent'});

  // Dates
  static const List<String> _weekdayKeys = [
    'weekdayMon',
    'weekdayTue',
    'weekdayWed',
    'weekdayThu',
    'weekdayFri',
    'weekdaySat',
    'weekdaySun',
  ];

  /// Localized weekday abbreviation. [weekday] follows DateTime.weekday:
  /// 1 (Monday) .. 7 (Sunday).
  String weekdayAbbr(int weekday) =>
      _t(_weekdayKeys[(weekday - 1) % 7]);

  /// A date labeled with its (localized) weekday, e.g. "Fri, 2026-07-24".
  /// The numeric part stays ISO in every locale for consistency.
  String dateWithDay(DateTime date) =>
      '${weekdayAbbr(date.weekday)}, ${formatIsoDate(date)}';

  static const List<String> _monthKeys = [
    'monthJan',
    'monthFeb',
    'monthMar',
    'monthApr',
    'monthMay',
    'monthJun',
    'monthJul',
    'monthAug',
    'monthSep',
    'monthOct',
    'monthNov',
    'monthDec',
  ];

  /// Localized full month name. [month] is 1 (January) .. 12 (December).
  String monthName(int month) => _t(_monthKeys[(month - 1) % 12]);

  // Recurring
  String get addRecurring => _t('addRecurring');
  String get editRecurring => _t('editRecurring');
  String get frequency => _t('frequency');
  String get nextDue => _t('nextDue');
  String get nextShort => _t('nextShort');
  String get fieldRequired => _t('fieldRequired');
  String get invalidValue => _t('invalidValue');
  String get noRecurring => _t('noRecurring');
  String get deleteRule => _t('deleteRule');
  String get addRecurringRule => _t('addRecurringRule');

  /// Localized label for a recurrence [frequency] value (a DbConstants.freq*).
  String freqLabel(String frequency) {
    switch (frequency) {
      case 'daily':
        return _t('freqDaily');
      case 'weekly':
        return _t('freqWeekly');
      case 'monthly':
        return _t('freqMonthly');
      case 'yearly':
        return _t('freqYearly');
      default:
        return frequency;
    }
  }

  // Investments
  String get totalInvested => _t('totalInvested');
  String get noInvestments => _t('noInvestments');
  String get latest => _t('latest');
  String get editInvestment => _t('editInvestment');
  String get enterInvestmentType => _t('enterInvestmentType');
  String get enterTypeOrPick => _t('enterTypeOrPick');
  String get optional => _t('optional');
  String contributions(int n) => n == 1
      ? _t('contributionOne')
      : _tArgs('contributionMany', {'n': '$n'});
  String totalInType(String type) => _tArgs('totalInType', {'type': type});
  String addToType(String type) => _tArgs('addToType', {'type': type});
  String get deleteContribution => _t('deleteContribution');
  String deleteContributionBody(String name, String amount) =>
      _tArgs('deleteContributionBody', {'name': name, 'amount': amount});

  // Backups & export
  String get backupRestore => _t('backupRestore');
  String get backupToDriveBtn => _t('backupToDriveBtn');
  String get restoreFromDriveBtn => _t('restoreFromDriveBtn');
  String get backupLocalJson => _t('backupLocalJson');
  String get restoreLocalJson => _t('restoreLocalJson');
  String get driveSetupNote => _t('driveSetupNote');
  String get encryptedBackup => _t('encryptedBackup');
  String get encryptedBackupNote => _t('encryptedBackupNote');
  String get encryptedBackupJson => _t('encryptedBackupJson');
  String get restoreEncryptedBackup => _t('restoreEncryptedBackup');
  String get downloadEncryptedBackup => _t('downloadEncryptedBackup');
  String get downloadShare => _t('downloadShare');
  String get downloadShareNote => _t('downloadShareNote');
  String get downloadExpensesCsv => _t('downloadExpensesCsv');
  String get downloadInvestmentsCsv => _t('downloadInvestmentsCsv');
  String get downloadFullJson => _t('downloadFullJson');
  String get importFromCsv => _t('importFromCsv');
  String get replaceAllTitle => _t('replaceAllTitle');
  String get replaceAllBody => _t('replaceAllBody');
  String get replace => _t('replace');
  String get newerBackupTitle => _t('newerBackupTitle');
  String get newerBackupBody => _t('newerBackupBody');
  String get overwrite => _t('overwrite');
  String get exported => _t('exported');
  String get passphrase => _t('passphrase');
  String get confirmPassphrase => _t('confirmPassphrase');
  String get passphraseMin => _t('passphraseMin');
  String get passphraseMismatch => _t('passphraseMismatch');
  String get passphraseForgotWarning => _t('passphraseForgotWarning');
  String get encryptBackupTitle => _t('encryptBackupTitle');
  String get encrypt => _t('encrypt');
  String get restoreAction => _t('restoreAction');
  String get noBackupYet => _t('noBackupYet');
  String get justNow => _t('justNow');
  String lastBackup(String ago) => _tArgs('lastBackup', {'ago': ago});
  String daysAgo(int n) =>
      n == 1 ? _tArgs('dayAgoOne', {'n': '$n'}) : _tArgs('dayAgoMany', {'n': '$n'});
  String hoursAgo(int n) => n == 1
      ? _tArgs('hourAgoOne', {'n': '$n'})
      : _tArgs('hourAgoMany', {'n': '$n'});
  String get backedUpToDrive => _t('backedUpToDrive');
  String get restoredFromDrive => _t('restoredFromDrive');
  String get localJsonCreated => _t('localJsonCreated');
  String get restoredLocalJson => _t('restoredLocalJson');
  String get encryptedBackupCreated => _t('encryptedBackupCreated');
  String get restoredEncrypted => _t('restoredEncrypted');
  String get subjectEncrypted => _t('subjectEncrypted');
  String get subjectExpenses => _t('subjectExpenses');
  String get subjectInvestments => _t('subjectInvestments');
  String get subjectFullBackup => _t('subjectFullBackup');

  // CSV import
  String columnN(int n) => _tArgs('columnN', {'n': '$n'});
  String get noValidRows => _t('noValidRows');
  String importedSkipped(int imported, int skipped) => _tArgs(
      'importedSkipped', {'imported': '$imported', 'skipped': '$skipped'});
  String get pickCsvHint => _t('pickCsvHint');
  String get chooseCsvFile => _t('chooseCsvFile');
  String get firstRowHeader => _t('firstRowHeader');
  String get dateColumn => _t('dateColumn');
  String get descriptionColumn => _t('descriptionColumn');
  String get amountColumn => _t('amountColumn');
  String get categoryColumnOptional => _t('categoryColumnOptional');
  String get typeColumnOptional => _t('typeColumnOptional');
  String get importAllRowsAs => _t('importAllRowsAs');
  String get preview => _t('preview');
  String get importAction => _t('importAction');
  String get chooseDifferentFile => _t('chooseDifferentFile');
  String get noValidRowsMapping => _t('noValidRowsMapping');
  String get noDescription => _t('noDescription');
  String willImportSkip(int n, int skip) =>
      _tArgs('willImportSkip', {'n': '$n', 'skip': '$skip'});

  // Monthly summary
  String get noTransactionsToInclude => _t('noTransactionsToInclude');
  String get statementTitle => _t('statementTitle');
  String statementSubject(String period) =>
      _tArgs('statementSubject', {'period': period});
  String get sharePdfStatement => _t('sharePdfStatement');
  String get net => _t('net');
  String get savingsRate => _t('savingsRate');
  String get expenseVsLastMonth => _t('expenseVsLastMonth');
  String get topCategories => _t('topCategories');

  // Category trends
  String get noExpenses12Months => _t('noExpenses12Months');
  String get spendingByCategory => _t('spendingByCategory');

  // Cash flow
  String get incomeVsExpense12 => _t('incomeVsExpense12');
  String get totalIncome => _t('totalIncome');
  String get totalExpense => _t('totalExpense');

  // Accounts
  String get deleteAccountTitle => _t('deleteAccountTitle');
  String deleteAccountBody(String name) =>
      _tArgs('deleteAccountBody', {'name': name});

  // Add expense
  String failedToSave(String error) =>
      _tArgs('failedToSave', {'error': error});

  // Tutorial
  String get tutStep1Title => _t('tutStep1Title');
  String get tutStep1Body => _t('tutStep1Body');
  String get tutStep2Title => _t('tutStep2Title');
  String get tutStep2Body => _t('tutStep2Body');
  String get tutStep3Title => _t('tutStep3Title');
  String get tutStep3Body => _t('tutStep3Body');
  String get tutStep4Title => _t('tutStep4Title');
  String get tutStep4Body => _t('tutStep4Body');
  String get tutStep5Title => _t('tutStep5Title');
  String get tutStep5Body => _t('tutStep5Body');
  String get tutStep6Title => _t('tutStep6Title');
  String get tutStep6Body => _t('tutStep6Body');

  // Widgets
  String get previousMonth => _t('previousMonth');
  String get nextMonth => _t('nextMonth');
  String get selectCategoriesToCompare => _t('selectCategoriesToCompare');
  String get noTransactions12Months => _t('noTransactions12Months');
  String get alertsTitle => _t('alertsTitle');
  String get billOverdue => _t('billOverdue');
  String get billDueToday => _t('billDueToday');
  String get billDueTomorrow => _t('billDueTomorrow');
  String billDueInDaysN(int n) => _tArgs('billDueInDaysN', {'n': '$n'});

  /// Localized display label for a stored payment-mode value (the DB keeps the
  /// English value; only the label shown to the user is translated).
  String paymentModeLabel(String mode) {
    switch (mode) {
      case 'Cash':
        return _t('pmCash');
      case 'Credit Card':
        return _t('pmCreditCard');
      case 'Debit Card':
        return _t('pmDebitCard');
      case 'UPI':
        return _t('pmUpi');
      case 'Other':
        return _t('pmOther');
      default:
        return mode;
    }
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations._values.containsKey(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
