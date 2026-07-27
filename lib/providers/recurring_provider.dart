import 'package:flutter/material.dart';
import '../models/recurring_rule.dart';
import '../services/db_service.dart';

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

  Future<void> toggleEnabled(RecurringRule rule) async {
    await DBService()
        .updateRecurringRule(rule.copyWith(enabled: !rule.enabled));
    await fetchRules();
  }
}
