import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:flutter/foundation.dart';

import '../models/recurring_rule.dart';
import 'recurring_service.dart';
import '../utils/alerts.dart';
import '../utils/app_logger.dart';
import '../utils/billing_cycle.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';
import 'sms_auto_capture.dart';

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

  // Disjoint id ranges so bill reminders, budget alerts, and credit-card
  // reminders never collide and can be cancelled independently. Each occupies
  // a 100000-wide band.
  static const _budgetIdBase = 50000;
  static const _billIdBase = 100000;
  static const _creditIdBase = 200000;
  static const _dailyReminderId = 300000;

  static const _smsChannelId = 'sms_capture';

  /// Payload of a captured-SMS notification; tapping one asks the app to
  /// open the SMS review queue.
  static const openSmsReview = 'sms_review';

  /// Set to a notification's payload when the user taps it (or launched the
  /// app by tapping it). The home screen listens, acts and clears it.
  final ValueNotifier<String?> openRequest = ValueNotifier(null);

  Future<void> init() async {
    if (_initialized) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) =>
            openRequest.value = response.payload,
      );
      await _initTimezone();
      _initialized = true;
      // A tap that started the app arrives here rather than through the
      // callback above.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        openRequest.value = launch?.notificationResponse?.payload;
      }
    } catch (e, st) {
      AppLogger.error('Notification init failed', e, st);
    }
  }

  Future<void> _initTimezone() async {
    if (_tzReady) return;
    try {
      tzdata.initializeTimeZones();
      final name = (await FlutterTimezone.getLocalTimezone()).identifier;
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

  NotificationDetails _details() {
    // Channel name/description show in the Android notification settings.
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Budget & bill alerts',
        channelDescription: 'Reminders for due bills and budget limits',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        // The body carries exact amounts ("Groceries: over budget by
        // ₹4,320.00"), so on a locked screen it would show the very figures
        // the app lock exists to hide. `private` keeps the title visible and
        // hides the content until the device is unlocked.
        visibility: NotificationVisibility.private,
      ),
    );
  }

  Future<void> _show(int id, String title, String body) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
          id: id, title: title, body: body, notificationDetails: _details());
    } catch (e) {
      AppLogger.error('Notification show failed', e);
    }
  }

  /// Shows the notification for a bank alert that just arrived. Tapping it
  /// opens the SMS review queue (see [openRequest]).
  Future<void> showSmsCapture(SmsCaptureNotice notice) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        id: notice.id,
        title: notice.title,
        body: notice.body,
        payload: openSmsReview,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _smsChannelId,
            'New transactions from SMS',
            channelDescription:
                'A bank alert arrived and is waiting to be reviewed',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            // The title carries the amount and the merchant; keep both off
            // a locked screen, as the other alerts do.
            visibility: NotificationVisibility.private,
          ),
        ),
      );
    } catch (e) {
      AppLogger.error('SMS capture notification failed', e);
    }
  }

  /// Clears the captured-SMS notifications still showing: once the review
  /// queue is open they have done their job.
  Future<void> cancelSmsCaptures() async {
    if (!_initialized) return;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      for (final n in await android?.getActiveNotifications() ??
          const <ActiveNotification>[]) {
        final id = n.id;
        if (id != null &&
            id >= SmsAutoCapture.idBase &&
            id < SmsAutoCapture.idBase + 100000) {
          await _plugin.cancel(id: id);
        }
      }
    } catch (e) {
      AppLogger.error('Clearing SMS capture notifications failed', e);
    }
  }

  /// How many of a rule's coming occurrences get a reminder at once.
  ///
  /// Reminders are only re-armed while the app is open. With just the next
  /// occurrence scheduled, a phone that went a month without the app being
  /// opened got one reminder and then none.
  static const billRemindersAhead = 6;

  /// The due dates of [rule] to remind about, soonest first: none for a rule
  /// that is no bill (income, a SIP, a paused rule), otherwise its next
  /// [billRemindersAhead] occurrences up to its end date. A plain daily rule
  /// gets only its next one, so a week away isn't a week of "due tomorrow".
  static List<DateTime> billReminderDues(RecurringRule rule) {
    if (!rule.enabled || rule.id == null) return const [];
    // A SIP isn't a bill: it is posted to the investments by itself.
    if (rule.isInvestment || rule.type == DbConstants.txIncome) {
      return const [];
    }
    // Keeps every id inside the bill band.
    if (rule.id! >= (_creditIdBase - _billIdBase) ~/ billRemindersAhead) {
      return const [];
    }
    final daily = rule.frequency == DbConstants.freqDaily && rule.interval == 1;
    final end = rule.endDate;
    final dues = <DateTime>[];
    var due = rule.nextDue;
    while (dues.length < (daily ? 1 : billRemindersAhead)) {
      if (end != null &&
          due.isAfter(DateTime(end.year, end.month, end.day, 23, 59, 59))) {
        break;
      }
      dues.add(due);
      due = RecurringService.nextFor(rule, due);
    }
    return dues;
  }

  /// (Re)schedules reminders for every enabled bill, [daysBefore] days before
  /// each of its coming due dates (see [billReminderDues]) at [hour]:00 local
  /// time. Rescheduled whenever the app is open and the rules change.
  Future<void> scheduleBillReminders(List<RecurringRule> rules,
      {int daysBefore = 1, int hour = 9}) async {
    if (!_initialized || !_tzReady) return;
    try {
      // Drop any bill reminders scheduled on a previous run before re-arming.
      // Bounded to the bill band so credit-card reminders (a higher band) are
      // left intact regardless of the order these two are called in.
      for (final p in await _plugin.pendingNotificationRequests()) {
        if (p.id >= _billIdBase && p.id < _creditIdBase) {
          await _plugin.cancel(id: p.id);
        }
      }
      final now = tz.TZDateTime.now(tz.local);
      for (final rule in rules) {
        final dues = billReminderDues(rule);
        for (var k = 0; k < dues.length; k++) {
          final due = dues[k];
          // TZDateTime normalizes an out-of-range day (the 0th → prev month).
          final when = tz.TZDateTime(
              tz.local, due.year, due.month, due.day - daysBefore, hour);
          if (!when.isAfter(now)) continue;
          await _plugin.zonedSchedule(
            id: _billIdBase + rule.id! * billRemindersAhead + k,
            title: 'Bill due soon',
            body: rule.askFirst
                ? '${rule.description} is due ${_dueLabel(daysBefore)}. '
                    'Open the app to confirm the amount.'
                : '${rule.description} ${formatMoneyExact(rule.amount)} is '
                    'due ${_dueLabel(daysBefore)}',
            scheduledDate: when,
            notificationDetails: _details(),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      }
    } catch (e, st) {
      AppLogger.error('Scheduling bill reminders failed', e, st);
    }
  }

  /// (Re)schedules a payment reminder for each credit-card statement in
  /// [reminders], [daysBefore] days before the due date at [hour]:00 local
  /// time. Rescheduled on each launch, like the bill reminders.
  Future<void> scheduleCreditCardReminders(List<CreditCardReminder> reminders,
      {int daysBefore = 3, int hour = 9}) async {
    if (!_initialized || !_tzReady) return;
    try {
      // Clear only this band's previous reminders before re-arming.
      for (final p in await _plugin.pendingNotificationRequests()) {
        if (p.id >= _creditIdBase && p.id < _creditIdBase + 100000) {
          await _plugin.cancel(id: p.id);
        }
      }
      final now = tz.TZDateTime.now(tz.local);
      for (final r in reminders) {
        final due = r.dueDate;
        final when = tz.TZDateTime(
            tz.local, due.year, due.month, due.day - daysBefore, hour);
        if (!when.isAfter(now)) continue;
        await _plugin.zonedSchedule(
          id: _creditIdBase + r.accountId,
          title: 'Credit card payment due',
          body:
              '${r.accountName}: ${formatMoneyInExact(r.symbol, r.amountDue)} '
              'due ${_dueLabel(daysBefore)}',
          scheduledDate: when,
          notificationDetails: _details(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e, st) {
      AppLogger.error('Scheduling credit card reminders failed', e, st);
    }
  }

  /// (Re)schedules the daily "log today's spending" reminder at [minutes]
  /// after midnight, or cancels it when [minutes] is null. Repeats every day;
  /// when [loggedToday], the first one is tomorrow's, so a day that already
  /// has an entry isn't nagged. Re-armed whenever the data changes, so adding
  /// a transaction later in the day moves it past today too.
  Future<void> scheduleDailyReminder(int? minutes,
      {required bool loggedToday}) async {
    if (!_initialized || !_tzReady) return;
    try {
      await _plugin.cancel(id: _dailyReminderId);
      if (minutes == null) return;
      final now = tz.TZDateTime.now(tz.local);
      final when = nextDailyReminder(now, minutes, loggedToday: loggedToday);
      await _plugin.zonedSchedule(
        id: _dailyReminderId,
        title: 'Anything to log today?',
        body: 'Take a few seconds to add today\'s spending.',
        scheduledDate: tz.TZDateTime(
            tz.local, when.year, when.month, when.day, when.hour, when.minute),
        notificationDetails: _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        // Repeat at this time every day.
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e, st) {
      AppLogger.error('Scheduling the daily reminder failed', e, st);
    }
  }

  /// When the next daily reminder at [minutes] after midnight should fire,
  /// given [now]: today if that time is still ahead and nothing was logged
  /// today, otherwise tomorrow.
  static DateTime nextDailyReminder(DateTime now, int minutes,
      {required bool loggedToday}) {
    final today =
        DateTime(now.year, now.month, now.day, minutes ~/ 60, minutes % 60);
    if (!loggedToday && today.isAfter(now)) return today;
    return DateTime(
        now.year, now.month, now.day + 1, minutes ~/ 60, minutes % 60);
  }

  String _dueLabel(int daysBefore) => daysBefore <= 0
      ? 'today'
      : daysBefore == 1
          ? 'tomorrow'
          : 'in $daysBefore days';

  /// Stable per-category notification id from a persistent map, so two
  /// categories can never collide and overwrite each other's notification
  /// (the previous `hashCode % 1000` scheme could).
  Future<int> _budgetNotificationId(
      SharedPreferences prefs, String category) async {
    const mapKey = 'budget_notif_ids';
    final ids = Map<String, dynamic>.from(
        jsonDecode(prefs.getString(mapKey) ?? '{}') as Map);
    var id = ids[category] as int?;
    if (id == null) {
      id = ids.length;
      ids[category] = id;
      await prefs.setString(mapKey, jsonEncode(ids));
    }
    return _budgetIdBase + id;
  }

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
          await _budgetNotificationId(prefs, a.category),
          a.isOver ? 'Over budget' : 'Budget warning',
          a.isOver
              ? '${a.category}: over budget by ${formatMoneyExact(a.spent - a.budget)}'
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
