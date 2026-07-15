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
  int totalBaseBalance() => _accounts.fold<int>(
      0, (sum, a) => sum + (baseBalanceOf(a) ?? 0));

  Future<void> fetchAccounts() async {
    _accounts = await DBService().getAccounts();
    await _recomputeBalances();
    _balances.removeWhere(
        (id, _) => !_accounts.any((account) => account.id == id));
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

  Future<void> addAccount(Account account) async {
    await DBService().insertAccount(account);
    await fetchAccounts();
  }

  Future<void> updateAccount(Account account) async {
    await DBService().updateAccount(account);
    await fetchAccounts();
  }

  Future<void> deleteAccount(int id) async {
    await DBService().deleteAccount(id);
    await fetchAccounts();
  }

  /// Recompute balances after transactions change.
  Future<void> refreshBalances() async {
    await _recomputeBalances();
    notifyListeners();
  }
}
