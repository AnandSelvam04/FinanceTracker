import 'package:flutter/material.dart';
import '../models/account.dart';
import '../services/db_service.dart';

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

  int? balanceOf(Account account) => _balances[account.id];

  Future<void> fetchAccounts() async {
    _accounts = await DBService().getAccounts();
    for (final account in _accounts) {
      _balances[account.id!] = await DBService().getAccountBalance(account);
    }
    _balances.removeWhere(
        (id, _) => !_accounts.any((account) => account.id == id));
    notifyListeners();
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
    for (final account in _accounts) {
      _balances[account.id!] = await DBService().getAccountBalance(account);
    }
    notifyListeners();
  }
}
