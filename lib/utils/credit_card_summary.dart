import '../models/account.dart';
import 'alerts.dart' show calendarDaysBetween;
import 'billing_cycle.dart';

/// Credit cards drawing on one credit limit. Banks issue a Visa (or
/// Mastercard) and a RuPay card on the same limit: a 2,00,000 limit with
/// 10,000 spent on one and 5,000 on the other has 1,85,000 left on both. A
/// card on its own is a pool of one.
class LimitPool {
  /// The card that carries the limit; the others point to it through
  /// [Account.sharedLimitWith].
  final Account holder;

  /// Every card in the pool, [holder] first.
  final List<Account> cards;

  const LimitPool({required this.holder, required this.cards});

  /// More than one card shares the limit.
  bool get isShared => cards.length > 1;

  /// The shared limit: the holder's, or — should it have none — the first
  /// set on another card of the pool. Null when no card has one.
  int? get limit {
    for (final c in cards) {
      final l = c.creditLimit;
      if (l != null && l > 0) return l;
    }
    return null;
  }

  /// The pool's cards other than [card].
  List<Account> others(Account card) => [
        for (final c in cards)
          if (c.id != card.id) c
      ];
}

/// The card whose limit [card] uses: the one it points to, followed to the
/// end of the chain. A link that leads nowhere — to a deleted card, an
/// account that is not a credit card, one in another currency, or round in
/// a loop — is ignored, and the card keeps its own limit.
Account limitHolderOf(Account card, Map<int, Account> byId) {
  var current = card;
  final seen = <int?>{card.id};
  while (current.sharedLimitWith != null) {
    final next = byId[current.sharedLimitWith];
    if (next == null ||
        next.type != 'credit_card' ||
        next.currency != card.currency ||
        !seen.add(next.id)) {
      break;
    }
    current = next;
  }
  return current;
}

/// The limit pool of every credit card, by card id. Cards that share a limit
/// map to the same [LimitPool].
Map<int, LimitPool> limitPools(List<Account> accounts) {
  final cards = [
    for (final a in accounts)
      if (a.type == 'credit_card' && a.id != null) a
  ];
  final byId = {for (final c in cards) c.id!: c};
  final groups = <int, List<Account>>{};
  for (final c in cards) {
    groups.putIfAbsent(limitHolderOf(c, byId).id!, () => []).add(c);
  }
  final out = <int, LimitPool>{};
  for (final entry in groups.entries) {
    final holder = byId[entry.key]!;
    final pool = LimitPool(holder: holder, cards: [
      holder,
      for (final c in entry.value)
        if (c.id != holder.id) c,
    ]);
    for (final c in pool.cards) {
      out[c.id!] = pool;
    }
  }
  return out;
}

/// Where one credit card stands today: what has gone on it since the last
/// statement, what is owed on it, and the state of the last bill. Pure, so the
/// dashboard's Credit cards section can be tested without widgets.
class CreditCardSummary {
  final Account account;

  /// Start (inclusive) of the spending window [cycleSpend] covers: the day
  /// after the last statement, or — for a card with no billing cycle set — the
  /// first of this month.
  final DateTime periodStart;

  /// Charged to the card since [periodStart], in the card's own currency
  /// (minor units). Refunds on the card take it down.
  final int cycleSpend;

  /// What the card's balance says is owed (a negative balance, made
  /// positive). Zero when nothing is owed.
  final int owed;

  /// Money sitting on the card beyond what is owed — an overpaid bill or a
  /// refund after payment. Zero in the usual case.
  final int credit;

  /// The billing cycle, when the card has statement and due days set.
  final CreditCardCycle? cycle;

  /// Billed on the last statement; zero without a [cycle].
  final int statementAmount;

  /// Paid towards the card since the last statement.
  final int paidSinceStatement;

  /// Paid into the card since [periodStart]: bill payments, and refunds or
  /// cashback recorded as income on it.
  final int paidThisPeriod;

  /// Whole days from today to the last statement's due date; negative means
  /// overdue. Null without a [cycle].
  final int? daysUntilDue;

  /// The other cards this one shares its credit limit with; empty when it
  /// has a limit of its own.
  final List<Account> sharesLimitWith;

  /// The shared limit, when [sharesLimitWith] is not empty.
  final int? _poolLimit;

  /// Owed across every card on the shared limit, when [sharesLimitWith] is
  /// not empty.
  final int? _poolOwed;

  /// Unpaid principal of EMIs on this card (or the cards sharing its limit):
  /// not owed yet, but held against the limit until billed.
  final int emiBlocked;

  const CreditCardSummary({
    required this.account,
    required this.periodStart,
    required this.cycleSpend,
    required this.owed,
    this.credit = 0,
    this.cycle,
    this.statementAmount = 0,
    this.paidSinceStatement = 0,
    this.paidThisPeriod = 0,
    this.daysUntilDue,
    this.sharesLimitWith = const [],
    int? poolLimit,
    int? poolOwed,
    this.emiBlocked = 0,
  })  : _poolLimit = poolLimit,
        _poolOwed = poolOwed;

  bool get hasCycle => cycle != null;

  // --- Why "owed now" differs from what was spent this cycle --------------
  //
  // owed now = owed when tracking started + left over from earlier
  //            + spent this cycle − paid this cycle
  // Every part comes from the same rows as the card's balance, so they add
  // up to [owed] (less any [credit]) exactly.

  /// What the card's opening balance says was owed when tracking began (the
  /// set-up's "already owed when you start"); negative for a starting credit.
  int get openingOwed => -account.openingBalance;

  /// Owed at [periodStart], before this cycle's spending and payments.
  int get owedAtPeriodStart => (owed - credit) - cycleSpend + paidThisPeriod;

  /// Recorded spending before [periodStart] that no recorded payment has
  /// cleared — normally the last statement's bill. Negative when earlier
  /// payments or refunds exceed it.
  int get carriedFromEarlier => owedAtPeriodStart - openingOwed;

  /// More is owed than went on the card this cycle.
  bool get owesMoreThanCycle => owed > cycleSpend;

  /// The credit limit is shared with other cards.
  bool get isSharedLimit => sharesLimitWith.isNotEmpty;

  /// What is still to pay on the last statement.
  int get dueRemaining {
    final left = statementAmount - paidSinceStatement;
    return left > 0 ? left : 0;
  }

  /// The last statement billed something and it has all been paid.
  bool get billPaid => statementAmount > 0 && dueRemaining == 0;

  bool get isOverdue => dueRemaining > 0 && (daysUntilDue ?? 0) < 0;

  /// The card's credit limit — the shared one when [isSharedLimit] — when
  /// one is set.
  int? get limit {
    final l = isSharedLimit ? _poolLimit : account.creditLimit;
    return l != null && l > 0 ? l : null;
  }

  /// What counts against [limit]: owed on this card, plus on the cards it
  /// shares the limit with.
  int get limitUsed =>
      (isSharedLimit ? (_poolOwed ?? owed) : owed) + emiBlocked;

  /// Share of [limit] in use: [limitUsed] over the limit, from 0 up (above
  /// 1 when over the limit). Null without a limit.
  double? get usage => limit == null ? null : limitUsed / limit!;

  /// How much more can go on the card before it reaches [limit]; zero once
  /// at or over it. Null without a limit. Cards sharing a limit have the
  /// same amount available.
  int? get available {
    if (limit == null) return null;
    final left = limit! - limitUsed;
    return left > 0 ? left : 0;
  }

  /// How heavily the card is used, for the usage bar's colour.
  CreditUsageLevel? get usageLevel {
    final u = usage;
    if (u == null) return null;
    if (u >= highUsage) return CreditUsageLevel.high;
    if (u >= moderateUsage) return CreditUsageLevel.moderate;
    return CreditUsageLevel.low;
  }

  /// Above this share of the limit, usage starts to count against a credit
  /// score; the commonly quoted guideline is to stay under 30%.
  static const moderateUsage = 0.30;

  /// Close to maxing out the card.
  static const highUsage = 0.80;
}

/// See [CreditCardSummary.usageLevel].
enum CreditUsageLevel { low, moderate, high }

/// One summary per credit-card account, the cards with a bill still to pay
/// first (soonest due date first), then the rest by name.
///
/// [spendInRange] and [paidInRange] are the same window queries the bill
/// reminders use (see [creditCardReminders]); [balanceOf] is the card's
/// current balance in its own currency, null while it is still loading.
List<CreditCardSummary> creditCardSummaries({
  required List<Account> accounts,
  required DateTime now,
  required int Function(int accountId, DateTime start, DateTime endExclusive)
      spendInRange,
  required int Function(int accountId, DateTime start, DateTime endExclusive)
      paidInRange,
  required int? Function(Account account) balanceOf,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  final pools = limitPools(accounts);
  int owedOn(Account a) {
    final b = balanceOf(a) ?? 0;
    return b < 0 ? -b : 0;
  }

  // EMI loans hold the limit of the card they are on.
  final emiOn = <int, int>{};
  for (final a in accounts) {
    if (a.isLoan && a.sharedLimitWith != null) {
      emiOn[a.sharedLimitWith!] = (emiOn[a.sharedLimitWith!] ?? 0) + owedOn(a);
    }
  }

  final out = <CreditCardSummary>[];
  for (final a in accounts) {
    if (a.type != 'credit_card' || a.id == null) continue;
    final id = a.id!;
    final balance = balanceOf(a) ?? 0;
    final owed = balance < 0 ? -balance : 0;
    final credit = balance > 0 ? balance : 0;
    final pool = pools[id];
    final shared = pool != null && pool.isShared;
    final sharesWith = shared ? pool.others(a) : const <Account>[];
    final poolLimit = shared ? pool.limit : null;
    final poolOwed =
        shared ? pool.cards.fold<int>(0, (s, c) => s + owedOn(c)) : null;
    final emiBlocked = shared
        ? pool.cards.fold<int>(0, (s, c) => s + (emiOn[c.id] ?? 0))
        : (emiOn[id] ?? 0);

    if (!a.hasBillingCycle) {
      final start = DateTime(today.year, today.month, 1);
      out.add(CreditCardSummary(
        account: a,
        periodStart: start,
        cycleSpend: spendInRange(id, start, tomorrow),
        paidThisPeriod: paidInRange(id, start, tomorrow),
        owed: owed,
        credit: credit,
        sharesLimitWith: sharesWith,
        poolLimit: poolLimit,
        poolOwed: poolOwed,
        emiBlocked: emiBlocked,
      ));
      continue;
    }

    final cycle = computeCreditCardCycle(
        statementDay: a.statementDay!, dueDay: a.dueDay!, now: now);
    final paid = paidInRange(id, cycle.statementDate, tomorrow);
    out.add(CreditCardSummary(
      account: a,
      periodStart: cycle.billedUntil,
      cycleSpend: spendInRange(id, cycle.billedUntil, tomorrow),
      paidThisPeriod: paidInRange(id, cycle.billedUntil, tomorrow),
      owed: owed,
      credit: credit,
      cycle: cycle,
      statementAmount:
          spendInRange(id, cycle.billedCycleStart, cycle.billedUntil),
      paidSinceStatement: paid < 0 ? 0 : paid,
      daysUntilDue: calendarDaysBetween(today, cycle.dueDate),
      sharesLimitWith: sharesWith,
      poolLimit: poolLimit,
      poolOwed: poolOwed,
      emiBlocked: emiBlocked,
    ));
  }

  out.sort((x, y) {
    final xDue = x.dueRemaining > 0, yDue = y.dueRemaining > 0;
    if (xDue != yDue) return xDue ? -1 : 1;
    if (xDue) {
      final byDays = x.daysUntilDue!.compareTo(y.daysUntilDue!);
      if (byDays != 0) return byDays;
    }
    return x.account.name.toLowerCase().compareTo(y.account.name.toLowerCase());
  });
  return out;
}

/// Two cards that look like a pair a bank issued on one limit — "HDFC Visa"
/// and "HDFC RuPay" — and are not linked yet, so the Credit cards screen can
/// offer to link them. [holder] is the one that keeps the limit.
class LimitTwinSuggestion {
  final Account holder;
  final Account other;
  const LimitTwinSuggestion(this.holder, this.other);

  /// Stable key for remembering a dismissed suggestion.
  String get key {
    final a = holder.id!, b = other.id!;
    return a < b ? '$a-$b' : '$b-$a';
  }
}

/// The bank part of a card's name: its first word, lower-cased, letters and
/// digits only ("HDFC" in "HDFC Millennia RuPay"). Null when too short to
/// tell banks apart.
String? _issuerOf(String name) {
  final first = name.trim().split(RegExp(r'\s+')).first;
  final w = first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return w.length < 2 ? null : w;
}

/// Pairs of unlinked credit cards from the same issuer (same first word of
/// the name) in the same currency whose limits do not disagree: equal, or
/// set on only one of them. Each card is offered in at most one pair, and
/// pairs whose [LimitTwinSuggestion.key] is in [dismissed] are left out.
List<LimitTwinSuggestion> limitTwinSuggestions(List<Account> accounts,
    {Set<String> dismissed = const {}}) {
  final pools = limitPools(accounts);
  final solo = [
    for (final a in accounts)
      if (a.type == 'credit_card' &&
          a.id != null &&
          !(pools[a.id]?.isShared ?? false) &&
          _issuerOf(a.name) != null)
        a
  ]..sort((x, y) => x.id!.compareTo(y.id!));
  final used = <int>{};
  final out = <LimitTwinSuggestion>[];
  for (var i = 0; i < solo.length; i++) {
    final a = solo[i];
    if (used.contains(a.id)) continue;
    for (var j = i + 1; j < solo.length; j++) {
      final b = solo[j];
      if (used.contains(b.id) ||
          a.currency != b.currency ||
          _issuerOf(a.name) != _issuerOf(b.name)) {
        continue;
      }
      final la = a.creditLimit, lb = b.creditLimit;
      if (la != null && lb != null && la != lb) continue;
      // The card with the limit keeps it; with both or neither, the older.
      final s = (la == null && lb != null)
          ? LimitTwinSuggestion(b, a)
          : LimitTwinSuggestion(a, b);
      if (dismissed.contains(s.key)) continue;
      used.addAll([a.id!, b.id!]);
      out.add(s);
      break;
    }
  }
  return out;
}

/// The bank's available limit, from a card's last SMS alert, against the
/// app's. The reading is brought up to today with what was recorded on the
/// cards of the limit after the day it was sent, so the two compare like
/// for like.
class BankLimitCheck {
  /// The card whose alert gave the reading; a fix goes on its balance.
  final Account card;

  /// When the alert was sent.
  final DateTime readingAt;

  /// The bank's figure, brought up to today.
  final int bankAvailable;

  /// The app's available limit today.
  final int appAvailable;

  const BankLimitCheck({
    required this.card,
    required this.readingAt,
    required this.bankAvailable,
    required this.appAvailable,
  });

  /// Positive when the app thinks more is available than the bank does.
  int get difference => appAvailable - bankAvailable;

  /// Within a rupee: rounding, not a missing transaction.
  bool get matches => difference.abs() < 100;
}

/// Readings older than this are too stale to check against.
const bankReadingMaxAge = Duration(days: 45);

/// Checks [summary]'s available limit against the bank's: [readingFor]
/// gives the latest (amount, time) the bank sent for a card, and the
/// newest across the cards sharing the limit is used. Null without a limit
/// or a recent reading.
BankLimitCheck? bankLimitCheck({
  required CreditCardSummary summary,
  required ({int amount, DateTime at})? Function(Account card) readingFor,
  required DateTime now,
  required int Function(int accountId, DateTime start, DateTime endExclusive)
      spendInRange,
  required int Function(int accountId, DateTime start, DateTime endExclusive)
      paidInRange,
}) {
  final appAvailable = summary.available;
  if (appAvailable == null) return null;
  final cards = [summary.account, ...summary.sharesLimitWith];
  Account? from;
  ({int amount, DateTime at})? reading;
  for (final c in cards) {
    final r = readingFor(c);
    if (r == null) continue;
    if (reading == null || r.at.isAfter(reading.at)) {
      reading = r;
      from = c;
    }
  }
  if (reading == null || now.difference(reading.at) > bankReadingMaxAge) {
    return null;
  }
  // Recorded after the day of the reading: the bank's figure did not see it.
  final after = DateTime(reading.at.year, reading.at.month, reading.at.day + 1);
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  var bank = reading.amount;
  if (after.isBefore(tomorrow)) {
    for (final c in cards) {
      bank -= spendInRange(c.id!, after, tomorrow);
      bank += paidInRange(c.id!, after, tomorrow);
    }
  }
  return BankLimitCheck(
    card: from!,
    readingAt: reading.at,
    bankAvailable: bank,
    appAvailable: appAvailable,
  );
}
