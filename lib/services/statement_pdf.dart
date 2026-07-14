import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/expense.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';

/// Builds a formatted PDF statement for a period and returns the file so it
/// can be shared/downloaded. Uses a bundled font so the currency symbol
/// (₹, €, £, ¥, …) renders correctly.
class StatementPdf {
  StatementPdf._();

  static Future<File> build({
    required String title,
    required String periodLabel,
    required List<Expense> transactions,
  }) async {
    final regular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/FreeSans.ttf'));
    final bold =
        pw.Font.ttf(await rootBundle.load('assets/fonts/FreeSansBold.ttf'));
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);

    double income = 0, expense = 0;
    for (final t in transactions) {
      if (t.type == DbConstants.txIncome) {
        income += t.amount;
      } else if (t.type == DbConstants.txExpense) {
        expense += t.amount;
      }
    }
    final net = income - expense;

    final sorted = [...transactions]..sort((a, b) => a.date.compareTo(b.date));

    String signed(Expense e) {
      if (e.isIncome) return '+${formatMoney(e.amount)}';
      if (e.isTransfer) return formatMoney(e.amount);
      return '-${formatMoney(e.amount)}';
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title,
                    style: pw.TextStyle(
                        fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.Text(periodLabel,
                    style: const pw.TextStyle(
                        fontSize: 12, color: PdfColors.grey700)),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _summaryCell('Income', formatMoney(income)),
                _summaryCell('Expense', formatMoney(expense)),
                _summaryCell('Net', formatMoney(net)),
                _summaryCell('Transactions', '${transactions.length}'),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerRight,
            },
            headers: ['Date', 'Description', 'Category', 'Amount'],
            data: sorted
                .map((e) => [
                      _date(e.date),
                      e.description,
                      e.category,
                      signed(e),
                    ])
                .toList(),
          ),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final safe = periodLabel.replaceAll(RegExp(r'[^0-9A-Za-z]+'), '_');
    final file = File('${dir.path}/statement_$safe.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  static pw.Widget _summaryCell(String label, String value) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold)),
        ],
      );

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
