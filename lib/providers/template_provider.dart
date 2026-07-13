import 'package:flutter/material.dart';
import '../models/tx_template.dart';
import '../services/db_service.dart';

class TemplateProvider extends ChangeNotifier {
  List<TxTemplate> _templates = [];

  List<TxTemplate> get templates => _templates;

  Future<void> fetchTemplates() async {
    _templates = await DBService().getTemplates();
    notifyListeners();
  }

  Future<void> addTemplate(TxTemplate template) async {
    await DBService().insertTemplate(template);
    await fetchTemplates();
  }

  Future<void> deleteTemplate(int id) async {
    await DBService().deleteTemplate(id);
    await fetchTemplates();
  }
}
