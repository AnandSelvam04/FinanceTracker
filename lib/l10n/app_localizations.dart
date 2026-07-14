import 'package:flutter/material.dart';

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
    },
  };

  String _t(String key) =>
      _values[locale.languageCode]?[key] ?? _values['en']![key] ?? key;

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
