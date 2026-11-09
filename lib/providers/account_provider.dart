import 'package:flutter/material.dart';
import '../models/account.dart';
import '../services/db_service.dart';
import '../utils/currency_format.dart';

class AccountProvider extends ChangeNotifier {
  List<Account> _accounts = [];
  final Map<int, int> _balances = {};

  List<Account> get accounts => _accounts;

  Account? accountById(int? id) {
    if (id == null) return null;
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Balance in the account's own currency (minor units).
  int? balanceOf(Account account) => _balances[account.id];

  /// Balance converted to the app's base currency (minor units).
  int? baseBalanceOf(Account account) {
    final b = _balances[account.id];
    return b == null ? null : toBaseMinor(b, account.rate);
  }

  /// Sum of every account's balance, each converted to the base currency.
  int totalBaseBalance() =>
      _accounts.fold<int>(0, (sum, a) => sum + (baseBalanceOf(a) ?? 0));

  /// Exchange rate per account id, for consumers that hold amounts in an
  /// account's currency and need base-currency totals (see
  /// `ExpenseProvider.syncAccountRates`).
  Map<int, double> get ratesByAccount =>
      {for (final a in _accounts) a.id!: a.rate};

  Future<void> fetchAccounts() async {
    _accounts = await DBService().getAccounts();
    await _recomputeBalances();
    _balances
        .removeWhere((id, _) => !_accounts.any((account) => account.id == id));
    notifyListeners();
  }

  /// One grouped query for all accounts instead of four queries per account.
  Future<void> _recomputeBalances() async {
    final flows = await DBService().getAccountFlows();
    for (final account in _accounts) {
      _balances[account.id!] =
          account.openingBalance + (flows[account.id] ?? 0);
    }
  }

  /// Inserts [account] and returns its new id.
  Future<int> addAccount(Account account) async {
    final id = await DBService().insertAccount(account);
    await fetchAccounts();
    return id;
  }

  Future<void> updateAccount(Account account) async {
    await DBService().updateAccount(account);
    await fetchAccounts();
  }

  /// Makes [account]'s balance [target] by moving its opening balance by the
  /// difference: matching the bank's figure without touching transactions,
  /// spending or budgets.
  Future<void> setBalance(Account account, int target) async {
    final current = balanceOf(account) ?? account.openingBalance;
    final delta = target - current;
    if (delta == 0) return;
    await DBService().updateAccount(
        account.copyWith(openingBalance: account.openingBalance + delta));
    await fetchAccounts();
  }

  /// Puts [card] on [holder]'s credit limit — two cards a bank issues on one
  /// limit, like a Visa and a RuPay card. [holder] keeps the limit (taking
  /// [card]'s when it has none of its own), and [card] picks up the holder's
  /// billing days when it has none set.
  Future<void> shareLimit(Account card, Account holder) async {
    if (card.id == null || holder.id == null || card.id == holder.id) return;
    final limit = holder.creditLimit ?? card.creditLimit;
    if (limit != holder.creditLimit) {
      await DBService().updateAccount(holder.copyWith(creditLimit: limit));
    }
    final copyDays = !card.hasBillingCycle && holder.hasBillingCycle;
    await DBService().updateAccount(card.copyWith(
      sharedLimitWith: holder.id,
      clearCreditLimit: true,
      statementDay: copyDays ? holder.statementDay : null,
      dueDay: copyDays ? holder.dueDay : null,
    ));
    await fetchAccounts();
  }

  Future<void> deleteAccount(int id) async {
    await DBService().deleteAccount(id);
    await fetchAccounts();
  }

  Object? _seenInvestments;

  /// Investments can be paid from an account, so a change to them moves
  /// balances. Wired from the investment provider in main.dart, which hands
  /// over its list each time it changes (a new list on every fetch).
  void syncInvestments(Object investments) {
    if (identical(investments, _seenInvestments)) return;
    final firstSight = _seenInvestments == null;
    _seenInvestments = investments;
    if (!firstSight) refreshBalances();
  }

  /// Recompute balances after transactions change.
  Future<void> refreshBalances() async {
    await _recomputeBalances();
    notifyListeners();
  }
}
