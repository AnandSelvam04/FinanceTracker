import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/expense.dart';
import '../models/investment.dart';
import 'db_service.dart';
// Google Drive and Google Sign-In imports removed
// import 'package:http/http.dart' as http; // Removed, no longer needed
import 'package:csv/csv.dart';

// Export expenses to CSV

Future<File> exportExpensesToCsv() async {
  final expenses = await DBService().getExpenses();
  final List<List<dynamic>> rows = [
    ['ID', 'Title', 'Amount', 'Date', 'Category', 'PaymentMode'],
    ...expenses.map((e) => [
          e.id ?? '',
          e.title,
          e.amount,
          e.date.toIso8601String(),
          e.category,
          e.paymentMode,
        ]),
  ];
  String csvData = const ListToCsvConverter().convert(rows);
  final backupService = BackupService();
  final path = await backupService._localPath;
  final file = File('$path/expenses_export.csv');
  await file.writeAsString(csvData);
  return file;
}

// Export investments to CSV

Future<File> exportInvestmentsToCsv() async {
  final investments = await DBService().getInvestments();
  final List<List<dynamic>> rows = [
    ['ID', 'Name', 'Amount', 'Date', 'Type'],
    ...investments.map((i) => [
          i.id ?? '',
          i.name,
          i.amount,
          i.date.toIso8601String(),
          i.type,
        ]),
  ];
  String csvData = const ListToCsvConverter().convert(rows);
  final backupService = BackupService();
  final path = await backupService._localPath;
  final file = File('$path/investments_export.csv');
  await file.writeAsString(csvData);
  return file;
}

class BackupService {
  // Google Drive and Google Sign-In features removed

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> get _backupFile async {
    final path = await _localPath;
    return File('$path/finance_backup.json');
  }

  Future<void> backupToJson() async {
    final expenses = await DBService().getExpenses();
    final investments = await DBService().getInvestments();
    final data = {
      'expenses': expenses.map((e) => e.toMap()).toList(),
      'investments': investments.map((i) => i.toMap()).toList(),
    };
    final file = await _backupFile;
    await file.writeAsString(jsonEncode(data));
  }

  Future<void> restoreFromJson() async {
    final file = await _backupFile;
    if (!await file.exists()) return;
    final content = await file.readAsString();
    final data = jsonDecode(content);
    final db = DBService();
    for (var e in data['expenses']) {
      await db.insertExpense(Expense.fromMap(Map<String, dynamic>.from(e)));
    }
    for (var i in data['investments']) {
      await db
          .insertInvestment(Investment.fromMap(Map<String, dynamic>.from(i)));
    }
  }
}

// Google Drive authentication helper removed
