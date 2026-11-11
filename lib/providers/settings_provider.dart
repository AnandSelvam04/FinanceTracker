import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sms_auto_capture.dart';
import '../services/sms_service.dart';
import '../utils/app_theme.dart';
import '../utils/category_store.dart';
import '../utils/currency_format.dart';
import '../utils/dashboard_layout.dart';

/// User preferences persisted in SharedPreferences: currency, theme, app
/// lock, and the default account for new transactions.
class SettingsProvider extends ChangeNotifier {
  static const _kCurrency = 'currencySymbol';
  static const _kThemeMode = 'themeMode';
  static const _kLockTimeout = 'lockTimeoutSeconds';
  static const _kAppLock = 'biometricEnabled';
  static const _kDefaultAccount = 'defaultAccountId';
  static const _kAlertsEnabled = 'alertsEnabled';
  static const _kNotificationsEnabled = 'notificationsEnabled';
  static const _kSmsImportEnabled = 'smsImportEnabled';
  static const _kSeedColor = 'seedColorValue';
  static const _kDailyReminder = 'dailyReminderMinutes';
  static const _kHideAmounts = 'hideAmounts';
  static const _kBudgetRollover = 'budgetRollover';
  static const _kSmsAutoCapture = SmsAutoCapture.prefsKey;
  static const _kTrueBlack = 'trueBlackDark';
  static const _kWallpaperAccent = 'useWallpaperAccent';
  static const _kWallpaperAccentValue = 'wallpaperAccentValue';
  static const _kDashboardOrder = 'dashboardOrder';
  static const _kDashboardHidden = 'dashboardHidden';
  static const _kHomeShortcuts = 'homeShortcuts';

  /// Asks Android for the wallpaper's accent (Material You, Android 12+).
  static const _system = MethodChannel('finance_tracker/system');

  /// Accent colours the user can choose from; the first is the app default.
  static const List<Color> seedOptions = [
    AppTheme.seed, // indigo/blue (default)
    Color(0xFF2E7D32), // green
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
  bool _appLockEnabled = false;
  int? _defaultAccountId;
  bool _alertsEnabled = true;
  bool _notificationsEnabled = true;
  int? _dailyReminderMinutes;
  bool _hideAmounts = false;
  bool _budgetRollover = false;
  bool _trueBlack = false;
  bool _useWallpaperAccent = false;
  Color? _wallpaperAccent;
  List<String> _dashboardOrder = DashboardLayout.defaultOrder;
  Set<String> _dashboardHidden = const {};
  List<String> _homeShortcuts = DashboardLayout.defaultShortcuts;

  /// Off by default: reading the SMS inbox is the app's most intrusive
  /// permission, so it stays inert until the user turns it on.
  bool _smsImportEnabled = false;
  bool _smsAutoCapture = false;

  String get currencySymbol => _currencySymbol;
  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;

  /// The colour the theme is built from: the wallpaper's accent when the
  /// user chose to follow it and the phone offers one, else [seedColor].
  Color get themeSeed =>
      _useWallpaperAccent ? (_wallpaperAccent ?? _seedColor) : _seedColor;

  /// The wallpaper's accent colour, or null where the phone has none to
  /// offer (before Android 12, and off Android).
  Color? get wallpaperAccent => _wallpaperAccent;

  /// Whether the theme follows the wallpaper instead of a fixed accent.
  bool get useWallpaperAccent =>
      _useWallpaperAccent && _wallpaperAccent != null;

  /// Whether dark mode paints pure black backgrounds (for OLED screens).
  bool get trueBlack => _trueBlack;

  /// The dashboard's sections in the order shown, hidden ones included.
  List<String> get dashboardOrder => _dashboardOrder;

  /// Dashboard sections the user switched off.
  Set<String> get dashboardHidden => _dashboardHidden;

  /// The dashboard sections on show, in order.
  List<String> get dashboardSections => [
        for (final id in _dashboardOrder)
          if (!_dashboardHidden.contains(id)) id,
      ];

  /// The shortcut buttons on the dashboard, in order.
  List<String> get homeShortcuts => _homeShortcuts;

  int get lockTimeoutSeconds => _lockTimeoutSeconds;
  Duration get lockTimeout => Duration(seconds: _lockTimeoutSeconds);

  /// Whether the app asks for biometrics / the device PIN. Held here rather
  /// than read once at launch, so switching it takes effect straight away:
  /// turning it on used to leave the app unprotected until a full restart.
  bool get appLockEnabled => _appLockEnabled;
  int? get defaultAccountId => _defaultAccountId;

  /// Whether the dashboard shows proactive budget/bill alerts.
  bool get alertsEnabled => _alertsEnabled;

  /// Whether OS notifications for bills/budgets are enabled.
  bool get notificationsEnabled => _notificationsEnabled;

  bool get smsImportEnabled => _smsImportEnabled;

  /// Notify about a bank transaction as its SMS arrives. Only has an effect
  /// while [smsImportEnabled] is on.
  bool get smsAutoCapture => _smsImportEnabled && _smsAutoCapture;

  /// Time of the daily "log today's spending" reminder, as minutes after
  /// midnight; null when it is off (the default).
  int? get dailyReminderMinutes => _dailyReminderMinutes;

  /// Whether amounts on screen are masked (see [CurrencyFormat.hideAmounts]).
  bool get hideAmounts => _hideAmounts;

  /// Whether a budget's unspent amount (or overspend) carries into the next
  /// month's cap for the same category. Off by default.
  bool get budgetRollover => _budgetRollover;

  static const currencyOptions = ['₹', '\$', '€', '£', '¥', '₨', 'A\$', 'C\$'];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _currencySymbol = prefs.getString(_kCurrency) ?? '₹';
    _themeMode = _themeFromString(prefs.getString(_kThemeMode));
    _lockTimeoutSeconds = prefs.getInt(_kLockTimeout) ?? 15;
    _appLockEnabled = prefs.getBool(_kAppLock) ?? false;
    _defaultAccountId = prefs.getInt(_kDefaultAccount);
    _alertsEnabled = prefs.getBool(_kAlertsEnabled) ?? true;
    _notificationsEnabled = prefs.getBool(_kNotificationsEnabled) ?? true;
    _smsImportEnabled = prefs.getBool(_kSmsImportEnabled) ?? false;
    _smsAutoCapture = prefs.getBool(_kSmsAutoCapture) ?? false;
    _dailyReminderMinutes = prefs.getInt(_kDailyReminder);
    _hideAmounts = prefs.getBool(_kHideAmounts) ?? false;
    _budgetRollover = prefs.getBool(_kBudgetRollover) ?? false;
    CurrencyFormat.hideAmounts = _hideAmounts;
    _trueBlack = prefs.getBool(_kTrueBlack) ?? false;
    _useWallpaperAccent = prefs.getBool(_kWallpaperAccent) ?? false;
    _dashboardOrder =
        DashboardLayout.normaliseOrder(prefs.getString(_kDashboardOrder));
    _dashboardHidden =
        DashboardLayout.normaliseHidden(prefs.getString(_kDashboardHidden));
    _homeShortcuts =
        DashboardLayout.normaliseShortcuts(prefs.getString(_kHomeShortcuts));
    // The colour last read from the phone, so the theme is right from the
    // first frame; the phone is then asked again without holding up launch.
    final storedAccent = prefs.getInt(_kWallpaperAccentValue);
    _wallpaperAccent = storedAccent == null ? null : Color(storedAccent);
    unawaited(refreshWallpaperAccent());
    final storedSeed = prefs.getInt(_kSeedColor);
    _seedColor = storedSeed != null ? Color(storedSeed) : AppTheme.seed;
    SmsService.enabled = _smsImportEnabled;
    CurrencyFormat.symbol = _currencySymbol;
    // Loaded here so a restore, which reloads the settings, brings the
    // backup's categories back too.
    await CategoryStore.instance.load();
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

  /// Masks or reveals every amount on screen.
  ///
  /// The formatters read a static flag, and many widgets that show amounts
  /// are `const` and wouldn't rebuild on their own — so every element is
  /// marked for rebuild once, making the change land everywhere at once,
  /// including screens further down the navigation stack.
  Future<void> setHideAmounts(bool value) async {
    _hideAmounts = value;
    CurrencyFormat.hideAmounts = value;
    notifyListeners();
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHideAmounts, value);
  }

  Future<void> setBudgetRollover(bool value) async {
    _budgetRollover = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBudgetRollover, value);
    notifyListeners();
  }

  /// Turns the daily reminder on at [minutes] after midnight, or off (null).
  Future<void> setDailyReminderMinutes(int? minutes) async {
    _dailyReminderMinutes = minutes;
    final prefs = await SharedPreferences.getInstance();
    if (minutes == null) {
      await prefs.remove(_kDailyReminder);
    } else {
      await prefs.setInt(_kDailyReminder, minutes);
    }
    notifyListeners();
  }

  Future<void> setSmsImportEnabled(bool value) async {
    _smsImportEnabled = value;
    // Mirror it onto the service, which refuses to touch the inbox when off.
    SmsService.enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSmsImportEnabled, value);
    // Reading SMS off also stops listening for new ones.
    SmsAutoCapture.listen(on: smsAutoCapture);
    notifyListeners();
  }

  Future<void> setSmsAutoCapture(bool value) async {
    _smsAutoCapture = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSmsAutoCapture, value);
    SmsAutoCapture.listen(on: smsAutoCapture);
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
    // Picking a colour by hand stops following the wallpaper.
    _useWallpaperAccent = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kWallpaperAccent, false);
    await prefs.setInt(_kSeedColor, color.toARGB32());
    notifyListeners();
  }

  /// Reads the wallpaper's accent again: it changes when the wallpaper does.
  /// Only Android has one (and the channel that reports it); elsewhere —
  /// tests on the host included — this does nothing.
  Future<void> refreshWallpaperAccent() async {
    if (!Platform.isAndroid) return;
    Color? accent;
    try {
      final value = await _system.invokeMethod<int>('wallpaperAccent');
      if (value != null) accent = Color(value & 0xFFFFFFFF).withAlpha(255);
    } catch (_) {
      // A build without the channel: there is no accent to follow.
    }
    if (accent == _wallpaperAccent) return;
    _wallpaperAccent = accent;
    final prefs = await SharedPreferences.getInstance();
    if (accent == null) {
      await prefs.remove(_kWallpaperAccentValue);
    } else {
      await prefs.setInt(_kWallpaperAccentValue, accent.toARGB32());
    }
    notifyListeners();
  }

  Future<void> setUseWallpaperAccent(bool value) async {
    _useWallpaperAccent = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kWallpaperAccent, value);
    notifyListeners();
  }

  Future<void> setTrueBlack(bool value) async {
    _trueBlack = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTrueBlack, value);
    notifyListeners();
  }

  /// Saves the dashboard's section order and which of them are hidden.
  Future<void> setDashboardLayout({
    required List<String> order,
    required Set<String> hidden,
  }) async {
    _dashboardOrder = DashboardLayout.normaliseOrder(order.join(','));
    _dashboardHidden = DashboardLayout.normaliseHidden(hidden.join(','));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDashboardOrder, _dashboardOrder.join(','));
    await prefs.setString(_kDashboardHidden, _dashboardHidden.join(','));
    notifyListeners();
  }

  /// Saves which shortcut buttons the dashboard shows, in order.
  Future<void> setHomeShortcuts(List<String> ids) async {
    _homeShortcuts = DashboardLayout.normaliseShortcuts(ids.join(','));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHomeShortcuts, _homeShortcuts.join(','));
    notifyListeners();
  }

  Future<void> setLockTimeoutSeconds(int seconds) async {
    _lockTimeoutSeconds = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLockTimeout, seconds);
    notifyListeners();
  }

  Future<void> setAppLockEnabled(bool value) async {
    _appLockEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAppLock, value);
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

  /// Preferences carried in a backup, so restoring on a new phone brings back
  /// the currency (account exchange rates are relative to it), the default
  /// account, and the look. App lock and SMS import are left out: both need
  /// the new phone's own permission or biometrics before they can be on.
  static const _backedUpKeys = {
    _kCurrency: String,
    _kThemeMode: String,
    _kSeedColor: int,
    _kTrueBlack: bool,
    _kWallpaperAccent: bool,
    _kDashboardOrder: String,
    _kDashboardHidden: String,
    _kHomeShortcuts: String,
    _kLockTimeout: int,
    _kDefaultAccount: int,
    _kAlertsEnabled: bool,
    _kNotificationsEnabled: bool,
    _kDailyReminder: int,
    // The user's own categories and the icons and colours they chose.
    CategoryStore.prefsKey: String,
  };

  /// The backed-up preferences currently set.
  static Future<Map<String, Object>> exportForBackup() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final key in _backedUpKeys.keys)
        if (prefs.get(key) case final Object value) key: value,
    };
  }

  /// Writes preferences from a backup, skipping unknown keys and values of
  /// the wrong type. Call [load] afterwards to apply them to a live provider.
  static Future<void> importFromBackup(Map<dynamic, dynamic> values) async {
    final prefs = await SharedPreferences.getInstance();
    for (final MapEntry(:key, :value) in values.entries) {
      switch ((_backedUpKeys[key], value)) {
        case (const (String), final String v):
          await prefs.setString(key as String, v);
        case (const (int), final int v):
          await prefs.setInt(key as String, v);
        case (const (bool), final bool v):
          await prefs.setBool(key as String, v);
        default:
          break;
      }
    }
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
