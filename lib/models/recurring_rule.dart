import '../utils/db_constants.dart';

class RecurringRule {
  final int? id;
  final String description;

  /// Amount in minor units (paise/cents).
  final int amount;
  final String category;
  final String type; // expense | income
  final int? accountId;
  final String frequency; // daily | weekly | monthly | yearly
  final DateTime nextDue;

  /// Day-of-month the rule anchors to, so a monthly rule created on the
  /// 31st posts on the 31st again after a short month instead of drifting.
  final int anchorDay;
  final bool enabled;

  /// Last date the rule posts on (inclusive), or null to repeat indefinitely.
  /// Once nextDue passes this, the rule stops and is disabled.
  final DateTime? endDate;

  /// When true, each occurrence is logged as an investment contribution (a
  /// SIP) — [category] names the instrument type — instead of an expense.
  final bool isInvestment;

  RecurringRule({
    this.id,
    required this.description,
    required this.amount,
    required this.category,
    this.type = DbConstants.txExpense,
    this.accountId,
    required this.frequency,
    required this.nextDue,
    int? anchorDay,
    this.enabled = true,
    this.endDate,
    this.isInvestment = false,
  }) : anchorDay = anchorDay ?? nextDue.day;

  static const frequencies = [
    DbConstants.freqDaily,
    DbConstants.freqWeekly,
    DbConstants.freqMonthly,
    DbConstants.freqYearly,
  ];

  RecurringRule copyWith({DateTime? nextDue, bool? enabled}) => RecurringRule(
        id: id,
        description: description,
        amount: amount,
        category: category,
        type: type,
        accountId: accountId,
        frequency: frequency,
        nextDue: nextDue ?? this.nextDue,
        anchorDay: anchorDay,
        enabled: enabled ?? this.enabled,
        endDate: endDate,
        isInvestment: isInvestment,
      );

  Map<String, dynamic> toMap() => {
        DbConstants.colId: id,
        DbConstants.colDescription: description,
        DbConstants.colAmount: amount,
        DbConstants.colCategory: category,
        DbConstants.colType: type,
        DbConstants.colAccountId: accountId,
        DbConstants.colFrequency: frequency,
        DbConstants.colNextDue: nextDue.toIso8601String(),
        DbConstants.colAnchorDay: anchorDay,
        DbConstants.colEnabled: enabled ? 1 : 0,
        DbConstants.colEndDate: endDate?.toIso8601String(),
        DbConstants.colIsInvestment: isInvestment ? 1 : 0,
      };

  factory RecurringRule.fromMap(Map<String, dynamic> map) => RecurringRule(
        id: map[DbConstants.colId],
        description: map[DbConstants.colDescription] ?? '',
        amount: ((map[DbConstants.colAmount] ?? 0) as num).round(),
        category: map[DbConstants.colCategory] ?? 'Other',
        type: map[DbConstants.colType] ?? DbConstants.txExpense,
        accountId: map[DbConstants.colAccountId],
        frequency: map[DbConstants.colFrequency],
        nextDue: DateTime.parse(map[DbConstants.colNextDue]),
        anchorDay: map[DbConstants.colAnchorDay],
        enabled: (map[DbConstants.colEnabled] ?? 1) == 1,
        // Rows/backups from before schema v11 have no endDate column.
        endDate: map[DbConstants.colEndDate] == null
            ? null
            : DateTime.tryParse(map[DbConstants.colEndDate] as String),
        // Absent before schema v12; treat as a plain transaction rule.
        isInvestment: (map[DbConstants.colIsInvestment] ?? 0) == 1,
      );
}
