import 'package:flutter/material.dart';
import '../models/recurring_rule.dart';
import '../services/db_service.dart';
import '../services/recurring_service.dart';

class RecurringProvider extends ChangeNotifier {
  List<RecurringRule> _rules = [];

  List<RecurringRule> get rules => _rules;

  Future<void> fetchRules() async {
    _rules = await DBService().getRecurringRules();
    notifyListeners();
  }

  Future<void> addRule(RecurringRule rule) async {
    await DBService().insertRecurringRule(rule);
    await fetchRules();
  }

  Future<void> updateRule(RecurringRule rule) async {
    await DBService().updateRecurringRule(rule);
    await fetchRules();
  }

  Future<void> deleteRule(int id) async {
    await DBService().deleteRecurringRule(id);
    await fetchRules();
  }

  Future<void> toggleEnabled(RecurringRule rule, {DateTime? now}) async {
    final enabling = !rule.enabled;
    await DBService().updateRecurringRule(rule.copyWith(
      enabled: enabling,
      // Resuming a paused rule starts from its next occurrence. Keeping the old
      // nextDue made the catch-up loop post every occurrence missed while
      // paused — three Netflix charges for a three-month pause.
      nextDue: enabling ? resumeDate(rule, now ?? DateTime.now()) : null,
    ));
    await fetchRules();
  }

  /// The first occurrence of [rule] on or after [now]'s day, stepping from
  /// its current nextDue along its own schedule (so a monthly rule anchored
  /// on the 31st keeps its day). A nextDue already in the future is kept.
  static DateTime resumeDate(RecurringRule rule, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    var due = rule.nextDue;
    while (due.isBefore(today)) {
      due = RecurringService.nextDate(due, rule.frequency, rule.anchorDay);
    }
    return due;
  }
}
