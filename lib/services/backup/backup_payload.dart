/// What a backup holds: gathering it from the database, checking a backup's
/// shape before anything is wiped, and turning it back into table rows.
library;

import 'dart:convert';

import '../../models/account.dart';
import '../../models/budget.dart';
import '../../models/emi_plan.dart';
import '../../models/expense.dart';
import '../../models/investment.dart';
import '../../models/recurring_rule.dart';
import '../../models/savings_goal.dart';
import '../../models/tx_template.dart';
import '../../providers/settings_provider.dart';
import '../../utils/db_constants.dart';
import '../backup_crypto.dart';
import '../db_service.dart';
import 'backup_errors.dart';

/// The backup format written today.
///
/// v4: amounts are integer minor units (paise/cents).
/// v5: transfer rows may carry toAmount (destination-currency amount).
/// v6: adds savings goals. Older backups simply restore with none.
/// v7: adds the dismissed-SMS list, so a restore doesn't bring every
///     rejected message back into the review queue, and each investment
///     type's current value, and the app's settings (currency, theme,
///     default account...).
const backupFormatVersion = 7;

/// The table keys a backup payload carries, in the order they are restored.
const backupTableKeys = [
  'accounts',
  'expenses',
  'investments',
  'budgets',
  'recurring_rules',
  'templates',
  'goals',
  'emi_plans',
  'sms_ignored',
  'investment_values',
];

/// Assembles the full-data backup map shared by plain and encrypted backups.
Future<Map<String, dynamic>> collectBackupData() async {
  final db = DBService();
  final expenses = await db.getExpenses();
  final investments = await db.getInvestments();
  final budgets = await db.getBudgets();
  final accounts = await db.getAccounts();
  final recurringRules = await db.getRecurringRules();
  final templates = await db.getTemplates();
  final goals = await db.getGoals();
  final emiPlans = await db.getEmiPlans();
  final smsIgnored = await db.ignoredSourceRefs();
  final values = await db.getInvestmentValues();
  final settings = await SettingsProvider.exportForBackup();
  return {
    'version': backupFormatVersion,
    'expenses': expenses.map((e) => e.toMap()).toList(),
    'investments': investments.map((i) => i.toMap()).toList(),
    'budgets': budgets.map((b) => b.toMap()).toList(),
    'accounts': accounts.map((a) => a.toMap()).toList(),
    'recurring_rules': recurringRules.map((r) => r.toMap()).toList(),
    'templates': templates.map((t) => t.toMap()).toList(),
    'goals': goals.map((g) => g.toMap()).toList(),
    // Credit-card EMI plans; backups from before them restore with none.
    'emi_plans': emiPlans.map((p) => p.toMap()).toList(),
    'sms_ignored': smsIgnored,
    'settings': settings,
    'investment_values': [
      for (final e in values.entries)
        {
          DbConstants.colType: e.key,
          DbConstants.colAmount: e.value.amount,
          DbConstants.colDate: e.value.asOf.toIso8601String(),
        },
    ],
  };
}

/// Turns a backup file's contents into its payload, decrypting when it is
/// an encrypted envelope: first with this device's key (auto-backups and
/// older Drive copies), then with [passphrase]. Throws
/// [PassphraseRequiredException] when neither opens it.
Future<dynamic> decodeBackupContent(String content,
    {String? deviceKey, String? passphrase}) async {
  if (!BackupCrypto.isEncrypted(content)) return jsonDecode(content);
  if (deviceKey != null) {
    try {
      return jsonDecode(await BackupCrypto.decryptString(content, deviceKey));
    } catch (_) {
      // Not sealed with this device's key; try the passphrase.
    }
  }
  if (passphrase == null) throw PassphraseRequiredException();
  try {
    return jsonDecode(await BackupCrypto.decryptString(content, passphrase));
  } on FormatException {
    rethrow;
  } catch (_) {
    throw PassphraseRequiredException(wrongPassphrase: true);
  }
}

/// Returns [data] as a backup map, or throws [BackupFormatException] unless
/// it is shaped like one.
///
/// Restoring wipes the database before inserting, so every failure mode has
/// to be caught here rather than part-way through. Indexing `data['version']`
/// straight off a `dynamic` once turned a JSON file that wasn't an object (a
/// renamed CSV, say) into a raw `NoSuchMethodError`.
Map<String, dynamic> validateBackupPayload(Object? data) {
  if (data is! Map) {
    throw BackupFormatException(
        'That file is not a Finance Tracker backup — expected a JSON object, '
        'found ${data is List ? 'a list' : 'a ${data.runtimeType}'}.');
  }
  final version = data['version'];
  if (version != null && version is! num) {
    throw BackupFormatException(
        'That backup has an unreadable version field, so it may be corrupt.');
  }
  for (final key in backupTableKeys) {
    final table = data[key];
    if (table != null && table is! List) {
      throw BackupFormatException(
          'That backup is corrupt: "$key" should be a list of rows.');
    }
  }
  return Map<String, dynamic>.from(data);
}

/// The total number of rows across every table of a validated [data].
int backupRowCount(Map<String, dynamic> data) => backupTableKeys.fold<int>(
    0, (sum, key) => sum + ((data[key] as List?)?.length ?? 0));

/// Parses a validated backup payload into per-table row maps, running every
/// row through its model so a corrupt row throws here rather than reaching
/// the database. Shared by restore and verification.
Map<String, List<Map<String, Object?>>> rowsFromBackup(
    Map<String, dynamic> data) {
  // Backups before v4 stored amounts as major-unit doubles; convert them
  // to integer minor units so they match the current storage.
  final legacyAmounts = ((data['version'] ?? 0) as num) < 4;
  Map<String, dynamic> fix(Object? raw, List<String> amountKeys) {
    final map = Map<String, dynamic>.from(raw as Map);
    if (legacyAmounts) {
      for (final key in amountKeys) {
        final value = map[key];
        if (value is num) map[key] = (value * 100).round();
      }
    }
    return map;
  }

  List<Object?> table(String key) => (data[key] as List?) ?? const [];

  // Older backups lack some keys (accounts, budgets, …); those tables simply
  // restore empty. Ids are preserved because toMap includes them, keeping
  // account links intact.
  return <String, List<Map<String, Object?>>>{
    DbConstants.tableAccounts: [
      for (final a in table('accounts'))
        Account.fromMap(fix(a, [DbConstants.colOpeningBalance])).toMap(),
    ],
    DbConstants.tableExpenses: [
      for (final e in table('expenses'))
        Expense.fromMap(fix(e, [DbConstants.colAmount])).toMap(),
    ],
    DbConstants.tableInvestments: [
      for (final i in table('investments'))
        Investment.fromMap(fix(i, [DbConstants.colAmount])).toMap(),
    ],
    DbConstants.tableBudgets: [
      for (final b in table('budgets'))
        Budget.fromMap(fix(b, [DbConstants.colAmount])).toMap(),
    ],
    DbConstants.tableRecurringRules: [
      for (final r in table('recurring_rules'))
        RecurringRule.fromMap(fix(r, [DbConstants.colAmount])).toMap(),
    ],
    DbConstants.tableTemplates: [
      for (final t in table('templates'))
        TxTemplate.fromMap(fix(t, [DbConstants.colAmount])).toMap(),
    ],
    // Goals arrived in backup v6, long after the minor-unit switch, so
    // their amounts never need the legacy conversion.
    DbConstants.tableGoals: [
      for (final g in table('goals'))
        SavingsGoal.fromMap(Map<String, dynamic>.from(g as Map)).toMap(),
    ],
    DbConstants.tableEmiPlans: [
      for (final p in table('emi_plans'))
        EmiPlan.fromMap(Map<String, dynamic>.from(p as Map)).toMap(),
    ],
    DbConstants.tableSmsIgnored: [
      for (final ref in table('sms_ignored'))
        if (ref is String) {DbConstants.colSourceRef: ref},
    ],
    DbConstants.tableInvestmentValues: [
      for (final v in table('investment_values').cast<Map>())
        {
          DbConstants.colType: v[DbConstants.colType] as String,
          DbConstants.colAmount: (v[DbConstants.colAmount] as num).toInt(),
          DbConstants.colDate: DateTime.parse(v[DbConstants.colDate] as String)
              .toIso8601String(),
        },
    ],
  };
}
