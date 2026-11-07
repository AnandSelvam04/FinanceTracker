import '../utils/db_constants.dart';

/// A credit-card purchase converted to EMI: the bank takes the purchase off
/// the card, then bills [months] instalments of [monthlyAmount] on it, and
/// holds the unpaid principal against the card's limit meanwhile.
///
/// In the app the principal is a `loan` account ([loanAccountId]) linked to
/// the card. Each instalment is posted on its date as a transfer of the
/// principal part from the card to the loan, plus the interest part as an
/// expense on the card — so the card's bill rises by the instalment, the
/// loan winds down, and only the interest counts as spending.
class EmiPlan {
  final int? id;
  final int cardId;
  final int loanAccountId;
  final String description;

  /// Converted amount, minor units of the card's currency.
  final int principal;
  final int months;

  /// What each instalment bills, interest included. Equal to
  /// principal / months for a no-cost EMI.
  final int monthlyAmount;

  /// When the first instalment is billed; the rest follow monthly.
  final DateTime firstDate;

  const EmiPlan({
    this.id,
    required this.cardId,
    required this.loanAccountId,
    required this.description,
    required this.principal,
    required this.months,
    required this.monthlyAmount,
    required this.firstDate,
  });

  /// The principal part of instalment [k] (0-based); the last one takes the
  /// rounding so the parts add up to [principal].
  int principalPart(int k) {
    final base = principal ~/ months;
    return k == months - 1 ? principal - base * (months - 1) : base;
  }

  /// Total interest over the plan, spread evenly; the last instalment takes
  /// the rounding. Zero for a no-cost EMI — including the paise left over
  /// when the principal does not divide evenly into the months.
  int get totalInterest => interestFor(principal, months, monthlyAmount);

  static int interestFor(int principal, int months, int monthlyAmount) {
    final t = monthlyAmount * months - principal;
    return t > months ? t : 0;
  }

  int interestPart(int k) {
    final base = totalInterest ~/ months;
    return k == months - 1 ? totalInterest - base * (months - 1) : base;
  }

  /// Instalment [k]'s billing date: [firstDate]'s day each month, kept within
  /// shorter months.
  DateTime dateOf(int k) {
    final y = firstDate.year, m = firstDate.month + k;
    final lastDay = DateTime(y, m + 1, 0).day;
    final d = firstDate.day > lastDay ? lastDay : firstDate.day;
    return DateTime(y, m, d);
  }

  /// Instalments billed on or before [now].
  int billedBy(DateTime now) {
    var n = 0;
    while (n < months && !dateOf(n).isAfter(now)) {
      n++;
    }
    return n;
  }

  /// Marks the rows an instalment posts, so none is posted twice.
  String sourceRef(int k) => 'emi:$id:$k';

  Map<String, dynamic> toMap() => {
        DbConstants.colId: id,
        DbConstants.colEmiCardId: cardId,
        DbConstants.colEmiLoanId: loanAccountId,
        DbConstants.colDescription: description,
        DbConstants.colEmiPrincipal: principal,
        DbConstants.colEmiMonths: months,
        DbConstants.colEmiMonthly: monthlyAmount,
        DbConstants.colDate: firstDate.toIso8601String(),
      };

  factory EmiPlan.fromMap(Map<String, dynamic> m) => EmiPlan(
        id: m[DbConstants.colId] as int?,
        cardId: (m[DbConstants.colEmiCardId] as num).toInt(),
        loanAccountId: (m[DbConstants.colEmiLoanId] as num).toInt(),
        description: m[DbConstants.colDescription] as String,
        principal: (m[DbConstants.colEmiPrincipal] as num).toInt(),
        months: (m[DbConstants.colEmiMonths] as num).toInt(),
        monthlyAmount: (m[DbConstants.colEmiMonthly] as num).toInt(),
        firstDate: DateTime.parse(m[DbConstants.colDate] as String),
      );
}
