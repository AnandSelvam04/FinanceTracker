import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sms_service.dart';
import '../utils/app_theme.dart';
import '../utils/currency_format.dart';

/// User preferences persisted in SharedPreferences: currency, theme,
/// app-lock timeout, and the default account for new transactions.
class SettingsProvider extends ChangeNotifier {
  static const _kCurrency = 'currencySymbol';
  static const _kThemeMode = 'themeMode';
  static const _kLockTimeout = 'lockTimeoutSeconds';
  static const _kDefaultAccount = 'defaultAccountId';
  static const _kAlertsEnabled = 'alertsEnabled';
  static const _kNotificationsEnabled = 'notificationsEnabled';
  static const _kSmsImportEnabled = 'smsImportEnabled';
  static const _kSeedColor = 'seedColorValue';

  /// Accent colours the user can choose from; the first is the app default.
  static const List<Color> seedOptions = [
    AppTheme.seed, // green (default)
    Color(0xFF1565C0), // blue
    Color(0xFF6A1B9A), // purple
    Color(0xFFAD1457), // pink
    Color(0xFFEF6C00), // orange
    Color(0xFF00838F), // teal
    Color(0xFF37474F), // slate
  ];

  String _currencySymbol = '₹';
  ThemeMode _themeMode = ThemeMode.system;
  Color _seedColor = AppTheme.seed;
  int _lockTimeoutSeconds = 15;
  int? _defaultAccountId;
  bool _alertsEnabled = true;
  bool _notificationsEnabled = true;

  /// Off by default: reading the SMS inbox is the app's most intrusive
  /// permission, so it stays inert until the user turns it on.
  bool _smsImportEnabled = false;

  String get currencySymbol => _currencySymbol;
  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;
  int get lockTimeoutSeconds => _lockTimeoutSeconds;
  Duration get lockTimeout => Duration(seconds: _lockTimeoutSeconds);
  int? get defaultAccountId => _defaultAccountId;

  /// Whether the dashboard shows proactive budget/bill alerts.
  bool get alertsEnabled => _alertsEnabled;

  /// Whether OS notifications for bills/budgets are enabled.
  bool get notificationsEnabled => _notificationsEnabled;

  bool get smsImportEnabled => _smsImportEnabled;

  static const currencyOptions = ['₹', '\$', '€', '£', '¥', '₨', 'A\$', 'C\$'];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _currencySymbol = prefs.getString(_kCurrency) ?? '₹';
    _themeMode = _themeFromString(prefs.getString(_kThemeMode));
    _lockTimeoutSeconds = prefs.getInt(_kLockTimeout) ?? 15;
    _defaultAccountId = prefs.getInt(_kDefaultAccount);
    _alertsEnabled = prefs.getBool(_kAlertsEnabled) ?? true;
    _notificationsEnabled = prefs.getBool(_kNotificationsEnabled) ?? true;
    _smsImportEnabled = prefs.getBool(_kSmsImportEnabled) ?? false;
    final storedSeed = prefs.getInt(_kSeedColor);
    _seedColor = storedSeed != null ? Color(storedSeed) : AppTheme.seed;
    SmsService.enabled = _smsImportEnabled;
    CurrencyFormat.symbol = _currencySymbol;
    notifyListeners();
  }

  Future<void> setAlertsEnabled(bool value) async {
    _alertsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAlertsEnabled, value);
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool value) async {
    _notificationsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotificationsEnabled, value);
    notifyListeners();
  }

  Future<void> setSmsImportEnabled(bool value) async {
    _smsImportEnabled = value;
    // Mirror it onto the service, which refuses to touch the inbox when off.
    SmsService.enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSmsImportEnabled, value);
    notifyListeners();
  }

  Future<void> setCurrencySymbol(String symbol) async {
    _currencySymbol = symbol;
    CurrencyFormat.symbol = symbol;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCurrency, symbol);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, mode.name);
    notifyListeners();
  }

  Future<void> setSeedColor(Color color) async {
    _seedColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSeedColor, color.toARGB32());
    notifyListeners();
  }

  Future<void> setLockTimeoutSeconds(int seconds) async {
    _lockTimeoutSeconds = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLockTimeout, seconds);
    notifyListeners();
  }

  Future<void> setDefaultAccountId(int? id) async {
    _defaultAccountId = id;
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_kDefaultAccount);
    } else {
      await prefs.setInt(_kDefaultAccount, id);
    }
    notifyListeners();
  }

  static ThemeMode _themeFromString(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
