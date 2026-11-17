import '../models/account.dart';
import '../models/emi_plan.dart';
import '../models/expense.dart';
import '../utils/db_constants.dart';
import 'db_service.dart';

/// Converting card purchases to EMI, and billing the instalments as they
/// fall due. See [EmiPlan].
class EmiService {
  /// Category the interest part of an instalment is filed under.
  static const interestCategory = 'EMI interest';

  /// Converts [principal] on [card] to an EMI of [months] instalments of
  /// [monthlyAmount], the first billed on [firstDate].
  ///
  /// When [purchaseRecorded] is true (the purchase is already on the card in
  /// the app) the principal is moved off the card on [convertedOn], as the
  /// bank does; when false — an EMI from before tracking began — the loan
  /// simply starts owing it. Returns the new plan's id.
  static Future<int> convert({
    required Account card,
    required String description,
    required int principal,
    required int months,
    required int monthlyAmount,
    required DateTime firstDate,
    required DateTime convertedOn,
    bool purchaseRecorded = true,
  }) async {
    final db = DBService();
    final loanId = await db.insertAccount(Account(
      name: 'EMI · $description',
      type: 'loan',
      currency: card.currency,
      rate: card.rate,
      openingBalance: purchaseRecorded ? 0 : -principal,
      // Ties the loan to the card: its unpaid principal holds the limit.
      sharedLimitWith: card.id,
    ));
    final planId = await db.insertEmiPlan(EmiPlan(
      cardId: card.id!,
      loanAccountId: loanId,
      description: description,
      principal: principal,
      months: months,
      monthlyAmount: monthlyAmount,
      firstDate: firstDate,
    ));
    if (purchaseRecorded) {
      await db.insertExpense(Expense(
        description: 'Converted to EMI · $description',
        amount: principal,
        date: convertedOn,
        category: 'Transfer',
        paymentMode: 'Other',
        type: DbConstants.txTransfer,
        accountId: loanId,
        toAccountId: card.id,
        sourceRef: 'emi:$planId:convert',
      ));
    }
    return planId;
  }

  static Future<int>? _inFlight;

  /// Posts every instalment due by [now] that is not posted yet. Returns how
  /// many instalments were posted.
  ///
  /// One run at a time: launch, a resume and a rule change each start one,
  /// and two that overlapped both read the posted list before either wrote,
  /// so every due instalment was posted twice. A call made while a run is
  /// going waits for it and posts nothing itself (returning 0, so only the
  /// first caller reports and refreshes).
  static Future<int> postDue({DateTime? now}) {
    final running = _inFlight;
    if (running != null) return running.then((_) => 0, onError: (_) => 0);
    final run = _postDue(now ?? DateTime.now());
    _inFlight = run;
    return run.whenComplete(() => _inFlight = null);
  }

  static Future<int> _postDue(DateTime at) async {
    final db = DBService();
    final plans = await db.getEmiPlans();
    if (plans.isEmpty) return 0;
    final seen = await db.existingSourceRefs();
    var posted = 0;
    for (final p in plans) {
      final due = p.billedBy(at);
      for (var k = 0; k < due; k++) {
        final ref = p.sourceRef(k);
        if (seen.contains(ref)) continue;
        await postInstalment(p, k);
        posted++;
      }
    }
    return posted;
  }

  /// Instalment [k] of [plan]: its principal part moves from the card to the
  /// loan, and its interest part is an expense on the card.
  static Future<void> postInstalment(EmiPlan plan, int k) async {
    final db = DBService();
    final date = plan.dateOf(k);
    final label = 'EMI ${k + 1}/${plan.months} · ${plan.description}';
    await db.insertExpense(Expense(
      description: label,
      amount: plan.principalPart(k),
      date: date,
      category: 'Transfer',
      paymentMode: 'Credit Card',
      type: DbConstants.txTransfer,
      accountId: plan.cardId,
      toAccountId: plan.loanAccountId,
      sourceRef: plan.sourceRef(k),
    ));
    final interest = plan.interestPart(k);
    if (interest > 0) {
      await db.insertExpense(Expense(
        description: 'Interest · $label',
        amount: interest,
        date: date,
        category: interestCategory,
        paymentMode: 'Credit Card',
        accountId: plan.cardId,
        sourceRef: '${plan.sourceRef(k)}:interest',
      ));
    }
  }
}
