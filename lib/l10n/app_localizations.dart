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
