import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/expense.dart';
import '../utils/db_constants.dart';
import '../widgets/bill_payment_dialog.dart';
import '../models/account.dart';
import '../providers/account_provider.dart';
import '../services/card_limit_readings.dart';
import '../providers/expense_provider.dart';
import '../providers/investment_provider.dart';
import '../utils/app_colors.dart';
import '../utils/card_period.dart';
import '../utils/credit_card_summary.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/insets.dart';
import '../widgets/card_setup_dialog.dart';
import '../widgets/emi_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/reconcile_dialog.dart';
import 'account_detail_screen.dart';
import 'add_expense_screen.dart';
import 'add_transfer_screen.dart';
import '../utils/font_sizes.dart';
import '../utils/dimens.dart';

part 'credit_cards/card_tile.dart';
part 'credit_cards/overview_widgets.dart';

/// Every credit card in one place: what went on each over a period you pick,
/// what is owed now, how much of the limit is used, and where the bill
/// stands. Opened from the dashboard's Cards shortcut.
///
/// Set a card up once — limit, statement and due days, last four digits,
/// what was owed when you started — and it is tracked from then on by the
/// transactions recorded against it: SMS alerts, entries added by hand, and
/// bill payments.
class CreditCardsScreen extends StatefulWidget {
  /// Stands in for the clock in tests.
  final DateTime? now;
  const CreditCardsScreen({super.key, this.now});

  @override
  State<CreditCardsScreen> createState() => _CreditCardsScreenState();
}

class _CreditCardsScreenState extends State<CreditCardsScreen> {
  CardPeriodKind _kind = CardPeriodKind.cycle;
  DateTime? _customStart;
  DateTime? _customEnd;

  /// Pair suggestions ("these two look like one limit") the user turned
  /// down, by [LimitTwinSuggestion.key]; remembered across launches.
  Set<String> _dismissedTwins = {};

  /// Each card's last "Avl Lmt" from its SMS alerts, by last digits.
  Map<String, LimitReading> _readings = {};

  /// Each card's last reward points balance from SMS, by last digits.
  Map<String, LimitReading> _pointReadings = {};

  Future<void> _loadReadings() async {
    final r = await CardLimitReadings.load();
    final p = await CardLimitReadings.points.load();
    if (mounted && (r.isNotEmpty || p.isNotEmpty)) {
      setState(() {
        _readings = r;
        _pointReadings = p;
      });
    }
  }

  static const _dismissedTwinsKey = 'dismissedLimitTwins';

  DateTime get _now => widget.now ?? DateTime.now();

  Future<void> _loadDismissedTwins() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_dismissedTwinsKey) ?? const [];
      if (mounted && saved.isNotEmpty) {
        setState(() => _dismissedTwins = saved.toSet());
      }
    } catch (_) {
      // Preferences unavailable: suggestions simply show again.
    }
  }

  Future<void> _dismissTwin(LimitTwinSuggestion t) async {
    setState(() => _dismissedTwins = {..._dismissedTwins, t.key});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_dismissedTwinsKey, _dismissedTwins.toList());
    } catch (_) {}
  }

  Future<void> _linkTwin(LimitTwinSuggestion t) async {
    await context.read<AccountProvider>().shareLimit(t.other, t.holder);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${t.holder.name} and ${t.other.name} now share one '
            'limit')));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Fresh balances and card details, as the Accounts and Investments
      // screens load theirs on opening.
      context.read<AccountProvider>().fetchAccounts();
      context.read<InvestmentProvider>().fetchInvestments();
      // A cycle, or last month, can reach back into the previous year.
      _ensureLoaded(_now.year - 1, _now.year);
      _loadDismissedTwins();
      _loadReadings();
    });
  }

  Future<void> _ensureLoaded(int fromYear, int toYear) async {
    if (!mounted) return;
    await context
        .read<ExpenseProvider>()
        .ensureYearsLoaded([for (var y = fromYear; y <= toYear; y++) y]);
  }

  Future<void> _pickRange() async {
    final today = DateTime(_now.year, _now.month, _now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDateRange: _customStart == null
          ? DateTimeRange(
              start: DateTime(today.year, today.month, 1), end: today)
          : DateTimeRange(start: _customStart!, end: _customEnd!),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _kind = CardPeriodKind.custom;
      _customStart = picked.start;
      _customEnd = picked.end;
    });
    await _ensureLoaded(picked.start.year, picked.end.year);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountProvider>();
    final expenses = context.watch<ExpenseProvider>();
    final investments = context.watch<InvestmentProvider>();
    final now = _now;

    int spendIn(int id, DateTime from, DateTime to) =>
        expenses.spendOnAccountInRange(id, from, to) +
        investments.chargedToAccountInRange(id, from, to);

    final summaries = creditCardSummaries(
      accounts: accounts.accounts,
      now: now,
      spendInRange: spendIn,
      paidInRange: expenses.paidToAccountInRange,
      balanceOf: accounts.balanceOf,
    );
    final rows = [
      for (final s in summaries)
        () {
          final range = cardRange(s.account, _kind, now,
              customStart: _customStart, customEnd: _customEnd);
          final pts =
              CardLimitReadings.forCard(_pointReadings, s.account.last4);
          return _CardFigures(
            now: now,
            paymentGuesses: s.cycle == null
                ? const []
                : likelyBillPayments(
                    s,
                    expenses.expensesInRange(s.cycle!.statementDate,
                        DateTime(now.year, now.month, now.day + 1))),
            rewards: rewardEstimate(
              s.account,
              now: now,
              periodStart: s.periodStart,
              spendBetween: (from, to) =>
                  expenses.spendOnAccountInRange(s.account.id!, from, to),
              smsReading: pts == null ? null : (points: pts.amount, at: pts.at),
            ),
            bankCheck: bankLimitCheck(
              summary: s,
              readingFor: (c) {
                final r = CardLimitReadings.forCard(_readings, c.last4);
                return r == null ? null : (amount: r.amount, at: r.at);
              },
              now: now,
              spendInRange: spendIn,
              paidInRange: expenses.paidToAccountInRange,
            ),
            summary: s,
            range: range,
            spent: spendIn(s.account.id!, range.start, range.endExclusive),
            paidIn: expenses.paidToAccountInRange(
                s.account.id!, range.start, range.endExclusive),
          );
        }(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Credit cards'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_card),
            tooltip: 'Add a credit card',
            onPressed: () => showCardSetupDialog(context),
          ),
        ],
      ),
      body: rows.isEmpty
          ? EmptyState(
              icon: Icons.credit_card,
              title: 'No credit cards yet',
              message: 'Add a card with its limit and billing days, and its '
                  'spending is tracked from SMS alerts and the expenses you '
                  'add with it.',
              actionLabel: 'Add a credit card',
              onAction: () => showCardSetupDialog(context),
            )
          : ListView(
              padding: scrollPadding(context, all: Space.md),
              children: [
                _PeriodFilter(
                  kind: _kind,
                  customLabel: _kind == CardPeriodKind.custom
                      ? rows.first.range.label
                      : null,
                  onSelected: (k) {
                    setState(() => _kind = k);
                  },
                  onCustom: _pickRange,
                ),
                const SizedBox(height: Space.sm),
                _Totals(rows: rows),
                if (bestCardToday(summaries, now) case final best?)
                  _BestCardBanner(summary: best, now: now),
                for (final t in limitTwinSuggestions(accounts.accounts,
                    dismissed: _dismissedTwins))
                  _TwinSuggestion(
                    suggestion: t,
                    onLink: () => _linkTwin(t),
                    onDismiss: () => _dismissTwin(t),
                  ),
                for (final g in _groupByLimit(rows))
                  g.length == 1
                      ? _CardTile(figures: g.single)
                      : _SharedLimitGroup(rows: g),
                const _HowItWorks(),
              ],
            ),
    );
  }
}

/// The cards sharing [s]'s limit (itself included) are known by their lowest
/// id.
int _poolKey(CreditCardSummary s) => [
      s.account.id!,
      for (final c in s.sharesLimitWith) c.id!
    ].reduce((a, b) => a < b ? a : b);

/// [rows] in their order, with the cards sharing a limit gathered into one
/// group where the first of them appears.
List<List<_CardFigures>> _groupByLimit(List<_CardFigures> rows) {
  final groups = <int, List<_CardFigures>>{};
  final out = <List<_CardFigures>>[];
  for (final r in rows) {
    if (!r.summary.isSharedLimit) {
      out.add([r]);
      continue;
    }
    final key = _poolKey(r.summary);
    final g = groups[key];
    if (g == null) {
      final fresh = [r];
      groups[key] = fresh;
      out.add(fresh);
    } else {
      g.add(r);
    }
  }
  return out;
}

/// One card's figures for the chosen period, next to its standing ones.
class _CardFigures {
  final CreditCardSummary summary;
  final CardRange range;

  /// Charged to the card in [range], refunds taken off.
  final int spent;

  /// Paid into the card in [range]: bill payments, refunds, cashback.
  final int paidIn;

  /// The bank's available limit from SMS against the app's, when known.
  final BankLimitCheck? bankCheck;

  /// Today, for "buy today, pay by".
  final DateTime? now;

  /// The card's reward points, when it tracks them.
  final RewardEstimate? rewards;

  /// Expenses that look like this card's bill payment saved as spending.
  final List<Expense> paymentGuesses;
  const _CardFigures({
    this.rewards,
    this.paymentGuesses = const [],
    this.bankCheck,
    this.now,
    required this.summary,
    required this.range,
    required this.spent,
    required this.paidIn,
  });
}
