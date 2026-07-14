import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/currency_format.dart';

/// User preferences persisted in SharedPreferences: currency, theme,
/// app-lock timeout, and the default account for new transactions.
class SettingsProvider extends ChangeNotifier {
  static const _kCurrency = 'currencySymbol';
  static const _kThemeMode = 'themeMode';
  static const _kLockTimeout = 'lockTimeoutSeconds';
  static const _kDefaultAccount = 'defaultAccountId';

  String _currencySymbol = '₹';
  ThemeMode _themeMode = ThemeMode.system;
  int _lockTimeoutSeconds = 15;
  int? _defaultAccountId;

  String get currencySymbol => _currencySymbol;
  ThemeMode get themeMode => _themeMode;
  int get lockTimeoutSeconds => _lockTimeoutSeconds;
  Duration get lockTimeout => Duration(seconds: _lockTimeoutSeconds);
  int? get defaultAccountId => _defaultAccountId;

  static const currencyOptions = ['₹', '\$', '€', '£', '¥', '₨', 'A\$', 'C\$'];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _currencySymbol = prefs.getString(_kCurrency) ?? '₹';
    _themeMode = _themeFromString(prefs.getString(_kThemeMode));
    _lockTimeoutSeconds = prefs.getInt(_kLockTimeout) ?? 15;
    _defaultAccountId = prefs.getInt(_kDefaultAccount);
    CurrencyFormat.symbol = _currencySymbol;
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
