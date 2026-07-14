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
      );
}
