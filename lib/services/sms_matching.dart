import '../models/expense.dart';
import '../utils/db_constants.dart';
import 'category_memory.dart';
import 'sms_import.dart';

/// Matching parsed alerts against each other and against the ledger: folding
/// the two alerts one movement sends into a single transfer, and spotting an
/// alert the user already entered by hand. Reading a single message is
/// [SmsImport]'s job.
class SmsMatching {
  SmsMatching._();

  /// Folds the two alerts a single movement produces into one row.
  ///
  /// Moving money between accounts usually texts twice — the sending bank
  /// reports a debit, the receiving bank or card a credit. Imported as they
  /// stand that is one expense plus one income for a movement that changed no
  /// net worth at all. Two shapes are collapsed:
  ///
  ///  * a transfer that already names both accounts absorbs a single-sided
  ///    alert about either of them;
  ///  * a lone debit and a lone credit naming different accounts become one
  ///    transfer between them.
  ///
  /// Only same-amount messages inside [window] are paired, and the survivor
  /// carries the absorbed sourceRefs so a rescan does not re-offer them.
  static List<ParsedSms> collapseTransferPairs(
    List<ParsedSms> items, {
    Duration window = const Duration(days: 3),
  }) {
    final result = List<ParsedSms>.from(items);
    final dropped = <int>{};

    bool near(ParsedSms a, ParsedSms b) =>
        a.amount == b.amount &&
        a.date.difference(b.date).abs() <= window &&
        a.sourceRef != b.sourceRef;

    for (var i = 0; i < result.length; i++) {
      if (dropped.contains(i)) continue;
      for (var j = i + 1; j < result.length; j++) {
        if (dropped.contains(j)) continue;
        final a = result[i];
        final b = result[j];
        if (!near(a, b)) continue;

        // A two-sided transfer already describes the whole movement.
        final absorbed = _absorbs(a, b) ? j : (_absorbs(b, a) ? i : null);
        if (absorbed != null) {
          final keepIndex = absorbed == j ? i : j;
          result[keepIndex] = result[keepIndex].copyWith(alsoCoversRefs: [
            ...result[keepIndex].alsoCoversRefs,
            result[absorbed].sourceRef,
            ...result[absorbed].alsoCoversRefs,
          ]);
          dropped.add(absorbed);
          if (absorbed == i) break;
          continue;
        }

        // A bare debit here and a bare credit there are the two ends of one
        // transfer between them.
        final merged = _mergeLegs(a, b) ?? _mergeLegs(b, a);
        if (merged != null) {
          result[i] = merged;
          dropped.add(j);
        }
      }
    }

    return [
      for (var i = 0; i < result.length; i++)
        if (!dropped.contains(i)) result[i]
    ];
  }

  /// Whether [transfer] already covers the single account [other] names.
  static bool _absorbs(ParsedSms transfer, ParsedSms other) =>
      transfer.isTransfer &&
      !other.isTransfer &&
      !other.isRefund &&
      other.last4 != null &&
      (SmsImport.sameAccountRef(other.last4, transfer.last4) ||
          SmsImport.sameAccountRef(other.last4, transfer.toLast4));

  /// Combines a lone debit and a lone credit on different accounts.
  static ParsedSms? _mergeLegs(ParsedSms debit, ParsedSms credit) {
    if (debit.type != DbConstants.txExpense) return null;
    if (credit.type != DbConstants.txIncome) return null;
    if (debit.isTransfer || credit.isTransfer) return null;
    // A refund landing on a card the same week as an unrelated debit of the
    // same amount is money back from a merchant, not one end of a transfer.
    if (credit.isRefund || credit.isCashback) return null;
    final from = debit.last4;
    final to = credit.last4;
    if (from == null || to == null || SmsImport.sameAccountRef(from, to)) {
      return null;
    }
    return debit.copyWith(
      type: DbConstants.txTransfer,
      description: 'Transfer',
      toLast4: to,
      alsoCoversRefs: [
        ...debit.alsoCoversRefs,
        credit.sourceRef,
        ...credit.alsoCoversRefs,
      ],
    );
  }

  /// An already-recorded transaction that looks like [parsed] was entered by
  /// hand, or null when there is none.
  ///
  /// Rows imported from a message are skipped: they are already covered by
  /// the sourceRef check, and matching against those would flag a legitimate
  /// second purchase of the same amount. Rows from a CSV statement are still
  /// considered — the same spend often arrives both ways.
  ///
  /// [claimed] holds the rows already matched to other messages in the same
  /// scan: one hand-entered ₹100 lunch is the duplicate of one ₹100 alert,
  /// not of every ₹100 alert that day. The row returned is added to it. When
  /// several rows qualify, one naming the same merchant wins, then the one
  /// closest in date.
  static Expense? findDuplicate(
    ParsedSms parsed,
    int? accountId,
    List<Expense> existing, {
    Duration window = const Duration(days: 2),
    Set<Object>? claimed,
  }) {
    final wanted = parsed.signedAmount;
    final type = parsed.recordedType;
    Expense? best;
    var bestMerchant = false;
    Duration? bestGap;
    for (final e in existing) {
      if (SmsImport.isSmsSourceRef(e.sourceRef)) continue;
      if (e.amount != wanted || e.type != type) continue;
      final gap = e.date.difference(parsed.date).abs();
      if (gap > window) continue;
      // An unset account on either side is not evidence of a different
      // transaction, so it does not rule the match out.
      if (accountId != null &&
          e.accountId != null &&
          e.accountId != accountId) {
        continue;
      }
      if (claimed != null && claimed.contains(_claimKey(e))) continue;
      // A different name is not proof of a different purchase — "Lunch"
      // typed by hand is the same ₹499 as "SWIGGY" in the alert — so it only
      // ranks the candidates rather than ruling one out.
      final sameMerchant = sameMerchantName(e.description, parsed.description);
      final better = best == null ||
          (sameMerchant && !bestMerchant) ||
          (sameMerchant == bestMerchant && gap < bestGap!);
      if (better) {
        best = e;
        bestMerchant = sameMerchant;
        bestGap = gap;
      }
    }
    if (best != null) claimed?.add(_claimKey(best));
    return best;
  }

  static Object _claimKey(Expense e) => e.id ?? e;

  /// Whether two descriptions name the same merchant once a bank's noise is
  /// stripped ("SWIGGY 88213" and "Swiggy"), allowing one to contain the other
  /// ("AMAZON PAY" and "Amazon").
  static bool sameMerchantName(String a, String b) {
    final ka = CategoryMemory.merchantKey(a);
    final kb = CategoryMemory.merchantKey(b);
    if (ka.length < 3 || kb.length < 3) return false;
    return ka == kb || ka.contains(kb) || kb.contains(ka);
  }
}
