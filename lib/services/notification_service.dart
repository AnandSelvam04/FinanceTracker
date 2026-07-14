import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/recurring_rule.dart';
import '../utils/alerts.dart';
import '../utils/app_logger.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';

/// Wraps flutter_local_notifications for budget/bill reminders. Every call is
/// guarded so a device without notification support (or a unit-test host)
/// degrades to a no-op instead of crashing.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _tzReady = false;

  static const _channelId = 'finance_alerts';
  static const _channelName = 'Budget & bill alerts';
  static const _channelDesc = 'Reminders for due bills and budget limits';

  // Disjoint id ranges so bill reminders and budget alerts never collide and
  // can be cancelled independently.
  static const _billIdBase = 100000;
  static const _budgetIdBase = 50000;

  Future<void> init() async {
    if (_initialized) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _plugin.initialize(settings);
      await _initTimezone();
      _initialized = true;
    } catch (e, st) {
      AppLogger.error('Notification init failed', e, st);
    }
  }

  Future<void> _initTimezone() async {
    if (_tzReady) return;
    try {
      tzdata.initializeTimeZones();
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
      _tzReady = true;
    } catch (e) {
      AppLogger.error('Timezone init failed', e);
    }
  }

  /// Asks for the Android 13+ notification permission. Returns true when the
  /// user has granted it (or the platform doesn't gate it).
  Future<bool> requestPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (e) {
      AppLogger.error('Notification permission request failed', e);
      return false;
    }
  }

  NotificationDetails _details() => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      );

  Future<void> _show(int id, String title, String body) async {
    if (!_initialized) return;
    try {
      await _plugin.show(id, title, body, _details());
    } catch (e) {
      AppLogger.error('Notification show failed', e);
    }
  }

  /// (Re)schedules a reminder for every enabled expense bill, [daysBefore] days
  /// before its next due date at [hour]:00 local time. Rescheduled on each app
  /// launch, so we don't need a boot receiver to survive restarts.
  Future<void> scheduleBillReminders(List<RecurringRule> rules,
      {int daysBefore = 1, int hour = 9}) async {
    if (!_initialized || !_tzReady) return;
    try {
      // Drop any reminders scheduled on a previous run before re-arming.
      for (final p in await _plugin.pendingNotificationRequests()) {
        if (p.id >= _billIdBase) await _plugin.cancel(p.id);
      }
      final now = tz.TZDateTime.now(tz.local);
      for (final rule in rules) {
        if (!rule.enabled || rule.id == null) continue;
        if (rule.type != DbConstants.txExpense) continue;
        final due = rule.nextDue;
        // TZDateTime normalizes an out-of-range day (e.g. the 0th → prev month).
        final when = tz.TZDateTime(
            tz.local, due.year, due.month, due.day - daysBefore, hour);
        if (!when.isAfter(now)) continue;
        await _plugin.zonedSchedule(
          _billIdBase + rule.id!,
          'Bill due soon',
          '${rule.description} ${formatMoney(rule.amount)} is due '
              '${_dueLabel(daysBefore)}',
          when,
          _details(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (e, st) {
      AppLogger.error('Scheduling bill reminders failed', e, st);
    }
  }

  String _dueLabel(int daysBefore) => daysBefore <= 0
      ? 'today'
      : daysBefore == 1
          ? 'tomorrow'
          : 'in $daysBefore days';

  /// Fires a notification for each budget alert not already announced this
  /// month, so the user isn't re-notified on every launch.
  Future<void> notifyBudgetAlerts(List<BudgetAlert> alerts,
      {required int year, required int month}) async {
    if (!_initialized || alerts.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'notified_budget_${year}_$month';
      final already = prefs.getStringList(key)?.toSet() ?? <String>{};
      for (final a in alerts) {
        final tag = '${a.category}:${a.isOver ? 'over' : 'warn'}';
        if (already.contains(tag)) continue;
        already.add(tag);
        await _show(
          _budgetIdBase + (a.category.hashCode % 1000).abs(),
          a.isOver ? 'Over budget' : 'Budget warning',
          a.isOver
              ? '${a.category}: over budget by ${formatMoney(a.spent - a.budget)}'
              : '${a.category}: ${(a.ratio * 100).round()}% of budget used',
        );
      }
      await prefs.setStringList(key, already.toList());
    } catch (e) {
      AppLogger.error('Budget notification failed', e);
    }
  }

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (e) {
      AppLogger.error('Cancel notifications failed', e);
    }
  }
}
