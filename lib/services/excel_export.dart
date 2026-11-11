import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/expense.dart';
import '../models/investment.dart';
import '../utils/currency_format.dart';
import 'db_service.dart';
import '../utils/date_format.dart';

/// One worksheet: a header row and the rows under it. A cell is a `String`,
/// an `int` (a count), a `double` (money, shown to two decimals), a
/// `DateTime` (shown as a date) or null (left empty).
class ExcelSheet {
  final String name;
  final List<String> headers;
  final List<List<Object?>> rows;

  /// Column widths in characters; columns past the end keep Excel's default.
  final List<double> widths;

  const ExcelSheet({
    required this.name,
    required this.headers,
    required this.rows,
    this.widths = const [],
  });
}

/// Writes `.xlsx` workbooks.
///
/// An .xlsx file is a zip of a few small XML parts, so it is written directly
/// rather than through a spreadsheet package: the app only ever needs plain
/// tables with a bold header, money to two decimals and real dates (so Excel
/// and Google Sheets can sort, sum and pivot them, which a CSV's text dates
/// and amounts do not allow without conversion).
class ExcelExport {
  ExcelExport._();

  static const mimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  // Cell style indexes into the cellXfs list in [_styles].
  static const _styleHeader = 1;
  static const _styleMoney = 2;
  static const _styleDate = 3;

  /// The workbook's bytes.
  static List<int> encode(List<ExcelSheet> sheets) {
    assert(sheets.isNotEmpty);
    final names = _uniqueNames([for (final s in sheets) s.name]);
    final archive = Archive();
    void add(String path, String xml) =>
        archive.addFile(ArchiveFile.string(path, xml));

    add('[Content_Types].xml', _contentTypes(sheets.length));
    add('_rels/.rels', _rootRels);
    add('xl/workbook.xml', _workbook(names));
    add('xl/_rels/workbook.xml.rels', _workbookRels(sheets.length));
    add('xl/styles.xml', _styles);
    for (var i = 0; i < sheets.length; i++) {
      add('xl/worksheets/sheet${i + 1}.xml', _sheet(sheets[i]));
    }
    return ZipEncoder().encode(archive);
  }

  /// Writes [sheets] to `<name>.xlsx` in the app's documents folder.
  static Future<File> write(List<ExcelSheet> sheets,
      {required String name}) async {
    final dir = await getApplicationDocumentsDirectory();
    final safe = name.replaceAll(RegExp(r'[^0-9A-Za-z-]+'), '_');
    final file = File('${dir.path}/$safe.xlsx');
    await file.writeAsBytes(encode(sheets), flush: true);
    return file;
  }

  /// Writes every transaction and investment in the database to one
  /// workbook, for the Backup & Export screen.
  static Future<File> writeEverything() async {
    final db = DBService();
    final accounts = await db.getAccounts();
    final rates = {
      for (final a in accounts)
        if (a.id != null) a.id!: a.rate,
    };
    return write(
      reportSheets(
        periodLabel: 'All transactions',
        transactions: await db.getExpenses(),
        baseAmountOf: (e) {
          final rate = rates[e.accountId] ?? 1.0;
          return rate == 1.0 ? e.amount : toBaseMinor(e.amount, rate);
        },
        accountNames: {
          for (final a in accounts)
            if (a.id != null) a.id!: a.name,
        },
        investments: await db.getInvestments(),
      ),
      name: 'finance_tracker_all',
    );
  }

  /// The sheets of a report on [transactions]: a summary, every transaction,
  /// spending by category and — when the period covers more than one month —
  /// income and spending month by month.
  ///
  /// [baseAmountOf] gives a row's amount in the base currency (rows are
  /// stored in their account's own currency); every total uses it.
  static List<ExcelSheet> reportSheets({
    required String periodLabel,
    required List<Expense> transactions,
    required int Function(Expense) baseAmountOf,
    Map<int, String> accountNames = const {},
    List<Investment> investments = const [],
  }) {
    final rows = [...transactions]..sort((a, b) => a.date.compareTo(b.date));
    double major(int minor) => minor / 100;

    var income = 0, expense = 0;
    final byCategory = <String, ({int total, int count})>{};
    final byMonth = <(int, int), ({int income, int expense})>{};
    for (final e in rows) {
      final amount = baseAmountOf(e);
      final key = (e.date.year, e.date.month);
      final month = byMonth[key] ?? (income: 0, expense: 0);
      if (e.isIncome) {
        income += amount;
        byMonth[key] = (income: month.income + amount, expense: month.expense);
      } else if (e.isExpense) {
        expense += amount;
        byMonth[key] = (income: month.income, expense: month.expense + amount);
        final c = byCategory[e.category] ?? (total: 0, count: 0);
        byCategory[e.category] = (total: c.total + amount, count: c.count + 1);
      }
    }
    final net = income - expense;
    final categories = byCategory.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    final months = byMonth.keys.toList()
      ..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);

    String kind(Expense e) => e.isTransfer
        ? 'Transfer'
        : e.isIncome
            ? 'Income'
            : e.isRefund
                ? 'Refund'
                : 'Expense';
    // Signed the way a statement reads: money out negative, money in
    // positive, a transfer (which is neither) unsigned.
    double signed(Expense e) {
      final amount = major(baseAmountOf(e));
      if (e.isTransfer || e.isIncome) return amount;
      return -amount; // a refund is stored negative, so this comes out positive
    }

    return [
      ExcelSheet(
        name: 'Summary',
        headers: const ['Finance Tracker report'],
        widths: const [26, 22],
        rows: [
          ['Period', periodLabel],
          ['Currency', CurrencyFormat.symbol],
          ['Income', major(income)],
          ['Expense', major(expense)],
          ['Net', major(net)],
          [
            'Savings rate %',
            income > 0 ? (net * 1000 / income).round() / 10 : null
          ],
          ['Transactions', rows.length],
          if (investments.isNotEmpty) ...[
            [
              'Invested (net of withdrawals)',
              major(investments.fold(0, (s, i) => s + i.amount))
            ],
          ],
        ],
      ),
      ExcelSheet(
        name: 'Transactions',
        headers: const [
          'Date',
          'Type',
          'Description',
          'Category',
          'Account',
          'To account',
          'Payment mode',
          'Amount',
          'Note',
        ],
        widths: const [12, 10, 34, 20, 22, 22, 14, 14, 40],
        rows: [
          for (final e in rows)
            [
              DateTime(e.date.year, e.date.month, e.date.day),
              kind(e),
              e.description,
              e.isTransfer ? null : e.category,
              accountNames[e.accountId],
              accountNames[e.toAccountId],
              e.isTransfer || e.paymentMode.isEmpty ? null : e.paymentMode,
              signed(e),
              e.note,
            ],
        ],
      ),
      ExcelSheet(
        name: 'By category',
        headers: const ['Category', 'Spent', 'Share %', 'Transactions'],
        widths: const [26, 14, 10, 14],
        rows: [
          for (final c in categories)
            [
              c.key,
              major(c.value.total),
              expense > 0
                  ? (c.value.total * 1000 / expense).round() / 10
                  : null,
              c.value.count,
            ],
        ],
      ),
      if (months.length > 1)
        ExcelSheet(
          name: 'By month',
          headers: const ['Month', 'Income', 'Expense', 'Net'],
          widths: const [18, 14, 14, 14],
          rows: [
            for (final m in months)
              [
                formatMonthYear(m.$1, m.$2),
                major(byMonth[m]!.income),
                major(byMonth[m]!.expense),
                major(byMonth[m]!.income - byMonth[m]!.expense),
              ],
          ],
        ),
      if (investments.isNotEmpty)
        ExcelSheet(
          name: 'Investments',
          headers: const ['Date', 'Name', 'Type', 'Amount', 'Paid from'],
          widths: const [12, 34, 20, 14, 22],
          rows: [
            for (final i in [
              ...investments
            ]..sort((a, b) => a.date.compareTo(b.date)))
              [
                DateTime(i.date.year, i.date.month, i.date.day),
                i.name,
                i.type,
                major(i.amount),
                accountNames[i.accountId],
              ],
          ],
        ),
    ];
  }

  // --- XML parts -------------------------------------------------------------

  static const _xmlHead =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
  static const _nsMain =
      'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  static const _nsRel =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  static const _nsPkgRel =
      'http://schemas.openxmlformats.org/package/2006/relationships';

  static String _contentTypes(int sheets) => '$_xmlHead'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '${[
        for (var i = 1; i <= sheets; i++)
          '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      ].join()}'
      '</Types>';

  static const _rootRels = '$_xmlHead'
      '<Relationships xmlns="$_nsPkgRel">'
      '<Relationship Id="rId1" Type="$_nsRel/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';

  static String _workbook(List<String> names) => '$_xmlHead'
      '<workbook xmlns="$_nsMain" xmlns:r="$_nsRel"><sheets>'
      '${[
        for (var i = 0; i < names.length; i++)
          '<sheet name="${_escape(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'
      ].join()}'
      '</sheets></workbook>';

  static String _workbookRels(int sheets) => '$_xmlHead'
      '<Relationships xmlns="$_nsPkgRel">'
      '${[
        for (var i = 1; i <= sheets; i++)
          '<Relationship Id="rId$i" Type="$_nsRel/worksheet" Target="worksheets/sheet$i.xml"/>'
      ].join()}'
      '<Relationship Id="rId${sheets + 1}" Type="$_nsRel/styles" Target="styles.xml"/>'
      '</Relationships>';

  // Styles: 0 plain, 1 bold header, 2 money (#,##0.00), 3 date (yyyy-mm-dd).
  static const _styles = '$_xmlHead'
      '<styleSheet xmlns="$_nsMain">'
      '<numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy-mm-dd"/></numFmts>'
      '<fonts count="2">'
      '<font><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><name val="Calibri"/></font>'
      '</fonts>'
      '<fills count="2">'
      '<fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill>'
      '</fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="4">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
      '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
      '</cellXfs>'
      '</styleSheet>';

  static String _sheet(ExcelSheet sheet) {
    final b = StringBuffer('$_xmlHead<worksheet xmlns="$_nsMain">');
    // Keep the header in view while scrolling a long sheet.
    b.write('<sheetViews><sheetView workbookViewId="0">'
        '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
        '</sheetView></sheetViews>');
    if (sheet.widths.isNotEmpty) {
      b.write('<cols>');
      for (var i = 0; i < sheet.widths.length; i++) {
        b.write('<col min="${i + 1}" max="${i + 1}" '
            'width="${sheet.widths[i]}" customWidth="1"/>');
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    _row(b, 1, sheet.headers, header: true);
    for (var r = 0; r < sheet.rows.length; r++) {
      _row(b, r + 2, sheet.rows[r]);
    }
    b.write('</sheetData></worksheet>');
    return b.toString();
  }

  static void _row(StringBuffer b, int number, List<Object?> cells,
      {bool header = false}) {
    b.write('<row r="$number">');
    for (var c = 0; c < cells.length; c++) {
      final ref = '${columnName(c)}$number';
      final value = cells[c];
      switch (value) {
        case null:
          break;
        case DateTime d:
          b.write('<c r="$ref" s="$_styleDate"><v>${dateSerial(d)}</v></c>');
        case int n:
          b.write('<c r="$ref"><v>$n</v></c>');
        case double n when n.isFinite:
          b.write('<c r="$ref" s="$_styleMoney"><v>$n</v></c>');
        case double _:
          break;
        default:
          final text = '$value';
          if (text.isEmpty) break;
          // An inline string is never read as a formula, so a description
          // such as "=1+1" stays text.
          b.write('<c r="$ref" t="inlineStr"'
              '${header ? ' s="$_styleHeader"' : ''}>'
              '<is><t xml:space="preserve">${_escape(text)}</t></is></c>');
      }
    }
    b.write('</row>');
  }

  /// Spreadsheet column letters for a zero-based index: A, B, … Z, AA, AB.
  static String columnName(int index) {
    var n = index + 1;
    final letters = StringBuffer();
    final chars = <int>[];
    while (n > 0) {
      final rem = (n - 1) % 26;
      chars.add(65 + rem);
      n = (n - 1) ~/ 26;
    }
    for (final c in chars.reversed) {
      letters.writeCharCode(c);
    }
    return letters.toString();
  }

  /// Excel's day number for the calendar date of [d] (1 = 1 Jan 1900, with
  /// the format's phantom 29 Feb 1900 counted, as every spreadsheet expects).
  static int dateSerial(DateTime d) => DateTime.utc(d.year, d.month, d.day)
      .difference(DateTime.utc(1899, 12, 30))
      .inDays;

  static String _escape(String s) {
    final b = StringBuffer();
    for (final rune in s.runes) {
      switch (rune) {
        case 0x26:
          b.write('&amp;');
        case 0x3C:
          b.write('&lt;');
        case 0x3E:
          b.write('&gt;');
        case 0x22:
          b.write('&quot;');
        // Control characters are not allowed in XML 1.0 at all; tab and the
        // line breaks are the exceptions.
        case < 0x20 when rune != 0x09 && rune != 0x0A && rune != 0x0D:
          break;
        case 0xFFFE || 0xFFFF:
          break;
        default:
          b.writeCharCode(rune);
      }
    }
    return b.toString();
  }

  /// Sheet names Excel accepts: at most 31 characters, none of `[]:*?/\`,
  /// and no two alike.
  static List<String> _uniqueNames(List<String> names) {
    final used = <String>{};
    final out = <String>[];
    for (final raw in names) {
      var base = raw.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
      if (base.isEmpty) base = 'Sheet';
      if (base.length > 31) base = base.substring(0, 31);
      var name = base;
      for (var n = 2; !used.add(name.toLowerCase()); n++) {
        final suffix = ' $n';
        name =
            '${base.substring(0, base.length > 31 - suffix.length ? 31 - suffix.length : base.length)}$suffix';
      }
      out.add(name);
    }
    return out;
  }
}
