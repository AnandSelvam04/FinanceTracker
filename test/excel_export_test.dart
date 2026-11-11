import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/models/investment.dart';
import 'package:finance_tracker/services/excel_export.dart';
import 'package:finance_tracker/utils/db_constants.dart';

void main() {
  Map<String, String> parts(List<int> bytes) => {
        for (final f in ZipDecoder().decodeBytes(bytes).files)
          f.name: utf8.decode(f.content as List<int>),
      };

  Expense e(String description, int amount, DateTime date,
          {String category = 'Food',
          String type = DbConstants.txExpense,
          int? accountId,
          int? toAccountId,
          String? note}) =>
      Expense(
          description: description,
          amount: amount,
          date: date,
          category: category,
          paymentMode: 'UPI',
          type: type,
          accountId: accountId,
          toAccountId: toAccountId,
          note: note);

  final sample = [
    e('Swiggy', 45000, DateTime(2026, 3, 4), accountId: 1),
    e('Rent', 1800000, DateTime(2026, 3, 1), category: 'Rent', accountId: 1),
    e('Refund', -20000, DateTime(2026, 4, 2), accountId: 1),
    e('Salary', 9000000, DateTime(2026, 4, 1),
        category: 'Salary', type: DbConstants.txIncome, accountId: 1),
    e('Card bill', 500000, DateTime(2026, 4, 5),
        category: 'Transfer',
        type: DbConstants.txTransfer,
        accountId: 1,
        toAccountId: 2),
  ];

  List<ExcelSheet> report({List<Investment> investments = const []}) =>
      ExcelExport.reportSheets(
        periodLabel: 'Mar – Apr 2026',
        transactions: sample,
        baseAmountOf: (e) => e.amount,
        accountNames: const {1: 'HDFC', 2: 'Card'},
        investments: investments,
      );

  test('column letters and date serials match what Excel uses', () {
    expect(ExcelExport.columnName(0), 'A');
    expect(ExcelExport.columnName(25), 'Z');
    expect(ExcelExport.columnName(26), 'AA');
    expect(ExcelExport.columnName(701), 'ZZ');
    expect(ExcelExport.columnName(702), 'AAA');
    // Well-known serials.
    expect(ExcelExport.dateSerial(DateTime(1900, 3, 1)), 61);
    expect(ExcelExport.dateSerial(DateTime(2000, 1, 1)), 36526);
    expect(ExcelExport.dateSerial(DateTime(2026, 11, 11, 23, 59)), 46337);
  });

  test('a workbook has every part a reader needs', () {
    final files = parts(ExcelExport.encode(report()));
    expect(
        files.keys,
        containsAll([
          '[Content_Types].xml',
          '_rels/.rels',
          'xl/workbook.xml',
          'xl/_rels/workbook.xml.rels',
          'xl/styles.xml',
          'xl/worksheets/sheet1.xml',
          'xl/worksheets/sheet4.xml',
        ]));
    expect(files['xl/workbook.xml'], contains('name="Transactions"'));
    expect(files['xl/workbook.xml'], contains('name="By month"'));
  });

  test('the report totals income and spending, refunds netted', () {
    final sheets = report();
    final summary = {for (final r in sheets.first.rows) r[0]: r[1]};
    expect(summary['Income'], 90000.0);
    // 450 + 18000 - 200 refund.
    expect(summary['Expense'], 18250.0);
    expect(summary['Net'], 71750.0);
    expect(summary['Transactions'], 5);

    final byCategory = sheets.firstWhere((s) => s.name == 'By category');
    expect(byCategory.rows.first.take(2), ['Rent', 18000.0]);
    expect(byCategory.rows.last.take(2), ['Food', 250.0]);

    final byMonth = sheets.firstWhere((s) => s.name == 'By month');
    expect(byMonth.rows, [
      ['March 2026', 0.0, 18450.0, -18450.0],
      ['April 2026', 90000.0, -200.0, 90200.0],
    ]);
  });

  test('transactions are dated, signed and carry account names', () {
    final tx = report().firstWhere((s) => s.name == 'Transactions');
    // Oldest first.
    expect(tx.rows.first[2], 'Rent');
    final byName = {for (final r in tx.rows) r[2]: r};
    expect(byName['Swiggy']![0], DateTime(2026, 3, 4));
    expect(byName['Swiggy']![7], -450.0);
    expect(byName['Refund']![1], 'Refund');
    expect(byName['Refund']![7], 200.0);
    expect(byName['Salary']![7], 90000.0);
    expect(byName['Card bill']![1], 'Transfer');
    expect(byName['Card bill']![4], 'HDFC');
    expect(byName['Card bill']![5], 'Card');
    // A transfer has no category of its own.
    expect(byName['Card bill']![3], isNull);
  });

  test('a single month gets no By month sheet; investments get their own', () {
    final oneMonth = ExcelExport.reportSheets(
        periodLabel: 'March 2026',
        transactions: sample.take(2).toList(),
        baseAmountOf: (e) => e.amount);
    expect(oneMonth.map((s) => s.name), isNot(contains('By month')));

    final withInvestments = report(investments: [
      Investment(
          name: 'Index fund',
          amount: 500000,
          date: DateTime(2026, 3, 9),
          type: 'Mutual Funds'),
    ]);
    expect(withInvestments.last.name, 'Investments');
    expect(withInvestments.last.rows.single[3], 5000.0);
  });

  test('text is escaped and never becomes a formula', () {
    final files = parts(ExcelExport.encode([
      const ExcelSheet(name: 'A/B: [x]', headers: [
        'H'
      ], rows: [
        ['=SUM(A1) & <b>"x"</b>\u0001'],
        [null, 12, 3.5],
      ]),
      const ExcelSheet(name: 'A B   x', headers: ['H'], rows: []),
    ]));
    final sheet = files['xl/worksheets/sheet1.xml']!;
    expect(
        sheet, contains('=SUM(A1) &amp; &lt;b&gt;&quot;x&quot;&lt;/b&gt;</t>'));
    expect(sheet, isNot(contains('<f>')));
    expect(sheet, isNot(contains('\u0001')));
    expect(sheet, contains('<c r="B3"><v>12</v></c>'));
    expect(sheet, contains('<c r="C3" s="2"><v>3.5</v></c>'));
    // Characters a sheet name can't hold are dropped, and a clash renamed.
    expect(files['xl/workbook.xml'], contains('name="A B   x"'));
    expect(files['xl/workbook.xml'], contains('name="A B   x 2"'));
  });

  test('writes a sample for inspection when asked', () {
    const out = String.fromEnvironment('XLSX_OUT');
    if (out.isEmpty) return;
    File(out).writeAsBytesSync(ExcelExport.encode(report(investments: [
      Investment(
          name: 'Index fund',
          amount: 500000,
          date: DateTime(2026, 3, 9),
          type: 'Mutual Funds'),
    ])));
  });
}
