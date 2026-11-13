import '../utils/db_constants.dart';

class RecurringRule {
  final int? id;
  final String description;

  /// Amount in minor units (paise/cents).
  final int amount;
  final String category;
  final String type; // expense | income | transfer
  final int? accountId;

  /// Where a transfer rule's money goes (a loan being repaid, a card whose
  /// bill is paid, a savings account). Null for expense and income rules.
  final int? toAccountId;

  /// How many periods of [frequency] pass between occurrences: 2 with weekly
  /// is every two weeks, 3 with monthly is quarterly.
  final int interval;

  /// When true the rule never posts by itself. It shows as due and waits for
  /// the amount to be confirmed, for bills that differ each time.
  final bool askFirst;
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
    this.toAccountId,
    int interval = 1,
    this.askFirst = false,
  })  : anchorDay = anchorDay ?? nextDue.day,
        interval = interval < 1 ? 1 : interval;

  bool get isTransfer => type == DbConstants.txTransfer;

  /// How often the rule repeats, in words: "Monthly", "Every 2 weeks".
  String get frequencyLabel => describeFrequency(frequency, interval);

  static String describeFrequency(String frequency, int interval) {
    if (interval <= 1) {
      return switch (frequency) {
        DbConstants.freqDaily => 'Daily',
        DbConstants.freqWeekly => 'Weekly',
        DbConstants.freqMonthly => 'Monthly',
        DbConstants.freqYearly => 'Yearly',
        _ => frequency,
      };
    }
    final unit = switch (frequency) {
      DbConstants.freqDaily => 'days',
      DbConstants.freqWeekly => 'weeks',
      DbConstants.freqMonthly => 'months',
      DbConstants.freqYearly => 'years',
      _ => frequency,
    };
    return 'Every $interval $unit';
  }

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
        toAccountId: toAccountId,
        interval: interval,
        askFirst: askFirst,
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
        DbConstants.colToAccountId: toAccountId,
        DbConstants.colEveryN: interval,
        DbConstants.colAskFirst: askFirst ? 1 : 0,
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
        // The three below are absent before schema v23.
        toAccountId: (map[DbConstants.colToAccountId] as num?)?.toInt(),
        interval: (map[DbConstants.colEveryN] as num?)?.toInt() ?? 1,
        askFirst: (map[DbConstants.colAskFirst] ?? 0) == 1,
      );
}
