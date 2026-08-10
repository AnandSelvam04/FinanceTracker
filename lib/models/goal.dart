import '../utils/db_constants.dart';

/// A savings goal: a named target amount the user is working toward, with an
/// optional target date and the amount saved so far. Progress is tracked
/// manually (contributions the user records) rather than tied to a single
/// account, so a goal can be funded from cash, a bank account, or anywhere.
class Goal {
  int? id;
  String name;

  /// Target and saved amounts in minor units (paise/cents), consistent with
  /// every other money value in the app.
  int targetAmount;
  int savedAmount;

  /// Optional date the user wants to reach [targetAmount] by. Null means the
  /// goal has no deadline.
  DateTime? targetDate;

  Goal({
    this.id,
    required this.name,
    required this.targetAmount,
    this.savedAmount = 0,
    this.targetDate,
  });

  /// Fraction saved so far, 0.0–1.0. A zero (or negative) target reads as
  /// complete rather than dividing by zero.
  double get progress {
    if (targetAmount <= 0) return 1.0;
    return (savedAmount / targetAmount).clamp(0.0, 1.0).toDouble();
  }

  /// Whether the target has been reached.
  bool get isComplete => savedAmount >= targetAmount && targetAmount > 0;

  /// Amount still to save (never negative).
  int get remaining =>
      targetAmount - savedAmount > 0 ? targetAmount - savedAmount : 0;

  Map<String, dynamic> toMap() {
    return {
      DbConstants.colId: id,
      DbConstants.colName: name,
      DbConstants.colTargetAmount: targetAmount,
      DbConstants.colSavedAmount: savedAmount,
      DbConstants.colTargetDate: targetDate?.toIso8601String(),
    };
  }

  factory Goal.fromMap(Map<String, dynamic> map) {
    final rawDate = map[DbConstants.colTargetDate];
    return Goal(
      id: map[DbConstants.colId],
      name: map[DbConstants.colName] ?? '',
      targetAmount: (map[DbConstants.colTargetAmount] as num?)?.round() ?? 0,
      savedAmount: (map[DbConstants.colSavedAmount] as num?)?.round() ?? 0,
      targetDate: (rawDate is String && rawDate.isNotEmpty)
          ? DateTime.tryParse(rawDate)
          : null,
    );
  }
}
