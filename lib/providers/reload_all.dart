import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'account_provider.dart';
import 'budget_provider.dart';
import 'expense_provider.dart';
import 'goal_provider.dart';
import 'investment_provider.dart';
import 'recurring_provider.dart';
import 'settings_provider.dart';
import 'template_provider.dart';

/// Re-reads everything the app shows from the database (and preferences),
/// after the whole of it changed underneath: a restore, its undo, or erasing
/// all data. Returns a function that does it, taken from [context] up front
/// so the caller can await other work first without holding the context.
Future<void> Function() dataReloader(BuildContext context) {
  final expenses = context.read<ExpenseProvider>();
  final investments = context.read<InvestmentProvider>();
  final budgets = context.read<BudgetProvider>();
  final accounts = context.read<AccountProvider>();
  final recurring = context.read<RecurringProvider>();
  final templates = context.read<TemplateProvider>();
  final goals = context.read<GoalProvider>();
  final settings = context.read<SettingsProvider>();
  return () async {
    await expenses.reloadLoadedYears();
    await investments.fetchInvestments();
    await budgets.fetchBudgets();
    await accounts.fetchAccounts();
    await recurring.fetchRules();
    await templates.fetchTemplates();
    await goals.fetchGoals();
    // A full restore brings back the backup's settings too.
    await settings.load();
  };
}
