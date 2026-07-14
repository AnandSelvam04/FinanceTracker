import 'package:flutter/material.dart';

/// Lightweight, hand-written localization (no codegen). The app is
/// translation-ready: add a locale by adding its map to [_values] and its
/// [Locale] to [supportedLocales]. Strings are exposed as getters so a typo is
/// a compile error rather than a silent runtime fallback.
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [Locale('en')];

  static const Map<String, Map<String, String>> _values = {
    'en': {
      'appTitle': 'Finance Tracker',
      'howToUse': 'How to use',
      'navHome': 'Home',
      'navExpenses': 'Expenses',
      'navMore': 'More',
      'addTransaction': 'Add transaction',
      'addExpense': 'Add Expense',
      'addInvestment': 'Add Investment',
      'dashboardCharts': 'Dashboard & Charts',
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
    },
  };

  String _t(String key) =>
      _values[locale.languageCode]?[key] ?? _values['en']![key] ?? key;

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
