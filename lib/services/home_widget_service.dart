import 'dart:io';

import 'package:home_widget/home_widget.dart';

import '../utils/app_logger.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';

/// What the home-screen widget shows: this month's spending, today's, and an
/// Add button. The figures are worked out in the app and handed to the
/// widget as text (it cannot read the database), each time they change.
class HomeWidgetData {
  final String title;
  final String amount;
  final String detail;
  const HomeWidgetData(this.title, this.amount, this.detail);

  @override
  bool operator ==(Object other) =>
      other is HomeWidgetData &&
      other.title == title &&
      other.amount == amount &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(title, amount, detail);
}

/// The widget's text for [now]: [monthSpent] and [todaySpent] in base minor
/// units. With [locked] (the app lock is on) the figures are hidden, since
/// the home screen is visible to anyone holding the phone.
HomeWidgetData homeWidgetData({
  required DateTime now,
  required int monthSpent,
  required int todaySpent,
  required bool locked,
}) {
  final title = 'Spent in ${monthName(now.month)}';
  if (locked) {
    return HomeWidgetData(
        title, '${CurrencyFormat.symbol} •••••', 'Hidden while app lock is on');
  }
  return HomeWidgetData(
    title,
    formatMoneyExactRounded(monthSpent),
    'Today ${formatMoneyExactRounded(todaySpent)}',
  );
}

/// Whole rupees for the widget's small space, always showing the figure
/// (hide-amounts is for the app's own screen).
String formatMoneyExactRounded(int minor) =>
    '${CurrencyFormat.symbol}${groupDigits('${(minor / 100).round()}', symbol: CurrencyFormat.symbol)}';

/// Pushes [HomeWidgetData] to the Android widget.
class HomeWidgetService {
  HomeWidgetService._();

  /// The widget's provider class in android/app/src/main/kotlin.
  static const androidProvider =
      'com.example.finance_tracker.SpendWidgetProvider';

  /// The widget's Add button opens the app on this, and tapping the widget
  /// anywhere else on [openUri].
  static final addUri = Uri.parse('financetracker://add');
  static final openUri = Uri.parse('financetracker://open');

  static HomeWidgetData? _last;

  /// Only Android has the widget (and the plugin's channels). Elsewhere —
  /// tests on the host included — every call is a no-op.
  static bool get _supported => Platform.isAndroid;

  /// Sends [data] to the widget unless it is what was sent last. Never
  /// throws: a missing widget plugin (tests, other platforms) is ignored.
  static Future<void> push(HomeWidgetData data) async {
    if (!_supported || data == _last) return;
    _last = data;
    try {
      await HomeWidget.saveWidgetData<String>('title', data.title);
      await HomeWidget.saveWidgetData<String>('amount', data.amount);
      await HomeWidget.saveWidgetData<String>('detail', data.detail);
      await HomeWidget.updateWidget(qualifiedAndroidName: androidProvider);
    } catch (e) {
      AppLogger.info('Home widget not updated: $e');
    }
  }

  /// The link the app was opened from, when that was the widget.
  static Future<Uri?> launchedFrom() async {
    if (!_supported) return null;
    try {
      return await HomeWidget.initiallyLaunchedFromHomeWidget();
    } catch (_) {
      return null;
    }
  }

  /// Taps on the widget while the app is already running.
  static Stream<Uri?> get clicks {
    if (!_supported) return const Stream.empty();
    try {
      return HomeWidget.widgetClicked;
    } catch (_) {
      return const Stream.empty();
    }
  }
}
