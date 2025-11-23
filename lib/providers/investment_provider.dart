import 'package:flutter/material.dart';
import '../models/investment.dart';
import '../services/db_service.dart';

class InvestmentProvider extends ChangeNotifier {
  List<Investment> _investments = [];

  List<Investment> get investments => _investments;

  Future<void> fetchInvestments() async {
    _investments = await DBService().getInvestments();
    notifyListeners();
  }

  Future<void> addInvestment(Investment investment) async {
    await DBService().insertInvestment(investment);
    await fetchInvestments();
  }

  Future<void> updateInvestment(Investment investment) async {
    await DBService().updateInvestment(investment);
    await fetchInvestments();
  }

  Future<void> deleteInvestment(int id) async {
    await DBService().deleteInvestment(id);
    await fetchInvestments();
  }
}
