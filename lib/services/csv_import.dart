import '../models/expense.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';

/// Which CSV column index maps to each transaction field. Date, description,
/// and amount are required; the rest are optional.
class CsvColumnMapping {
  final int dateCol;
  final int descriptionCol;
  final int amountCol;
  final int? categoryCol;
  final int? typeCol;
  final String defaultType;
  final String defaultCategory;

  const CsvColumnMapping({
    required this.dateCol,
    required this.descriptionCol,
    required this.amountCol,
    this.categoryCol,
    this.typeCol,
    this.defaultType = DbConstants.txExpense,
    this.defaultCategory = 'Other',
  });
}

class CsvImportResult {
  final List<Expense> expenses;
  final int skipped;
  const CsvImportResult(this.expenses, this.skipped);
}

/// Parses rows (as produced by the csv package) into expenses using the given
/// column mapping. Rows with an unparseable date or amount are skipped.
CsvImportResult parseCsvExpenses(
  List<List<dynamic>> rows, {
  required bool hasHeader,
  required CsvColumnMapping mapping,
}) {
  final expenses = <Expense>[];
  var skipped = 0;
  final data = hasHeader && rows.isNotEmpty ? rows.sublist(1) : rows;

  String cell(List<dynamic> row, int? index) {
    if (index == null || index < 0 || index >= row.length) return '';
    return row[index]?.toString().trim() ?? '';
  }

  // Bank exports without a type column often encode direction in the sign:
  // negative is a debit, positive a credit. Only trust that when the file
  // actually contains a negative — otherwise an all-positive export would
  // have every row flipped to income.
  final signIndicatesType = mapping.typeCol == null &&
      data.any((row) {
        final v = tryParseCsvAmount(cell(row, mapping.amountCol));
        return v != null && v < 0;
      });

  for (final row in data) {
    if (row.every((c) => (c?.toString().trim() ?? '').isEmpty)) continue;
    final date = tryParseCsvDate(cell(row, mapping.dateCol));
    final amount = tryParseCsvAmount(cell(row, mapping.amountCol));
    if (date == null || amount == null) {
      skipped++;
      continue;
    }
    final category = cell(row, mapping.categoryCol);
    final type = signIndicatesType
        ? (amount < 0 ? DbConstants.txExpense : DbConstants.txIncome)
        : _normalizeType(cell(row, mapping.typeCol), mapping.defaultType);
    expenses.add(Expense(
      description: cell(row, mapping.descriptionCol),
      // Direction lives in `type`; the stored amount is always positive.
      amount: rupeesToMinor(amount.abs()),
      date: date,
      category: category.isEmpty ? mapping.defaultCategory : category,
      paymentMode: 'Other',
      type: type,
    ));
  }
  return CsvImportResult(expenses, skipped);
}

String _normalizeType(String raw, String fallback) {
  final v = raw.toLowerCase();
  if (v.contains('income') || v.contains('credit') || v == 'cr') {
    return DbConstants.txIncome;
  }
  if (v.contains('expense') || v.contains('debit') || v == 'dr') {
    return DbConstants.txExpense;
  }
  return fallback;
}

/// Accepts ISO dates and day-first dd/MM/yyyy or dd-MM-yyyy (common outside
/// the US). Returns null if it can't be parsed.
DateTime? tryParseCsvDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso;
  final m = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})$').firstMatch(s);
  if (m != null) {
    final day = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    var year = int.parse(m.group(3)!);
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    try {
      final d = DateTime(year, month, day);
      if (d.month != month || d.day != day) return null; // e.g. 31 Feb
      return d;
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// Strips currency symbols and thousands separators, returning the **signed**
/// amount, or null if the text holds no number.
///
/// Handles both conventions, because a bank export doesn't say which it uses:
/// `1,234.56` (US/UK) and `1.234,56` (most of Europe) both yield 1234.56. The
/// previous version stripped everything but digits, `.` and `-`, so
/// `"1.234,56"` collapsed to `"1.234"` and imported as ₹1.23 — silently wrong,
/// which is worse than refusing the row.
///
/// Disambiguation, in order:
///  * both separators present — the rightmost is the decimal point;
///  * one separator, appearing more than once — grouping (`1.234.567`);
///  * one separator with exactly three digits after it — grouping, since
///    money doesn't carry three decimal places (`1,234` is 1234);
///  * otherwise — a decimal point (`1,23` is 1.23).
///
/// Accounting-style negatives, `(1,234.56)`, are recognised alongside `-`.
double? tryParseCsvAmount(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;

  var negative = false;
  if (s.length > 2 && s.startsWith('(') && s.endsWith(')')) {
    negative = true;
    s = s.substring(1, s.length - 1);
  }

  s = s.replaceAll(RegExp(r'[^0-9.,\-]'), '');
  if (s.contains('-')) {
    negative = true;
    s = s.replaceAll('-', '');
  }
  if (s.isEmpty || !RegExp(r'\d').hasMatch(s)) return null;

  final lastDot = s.lastIndexOf('.');
  final lastComma = s.lastIndexOf(',');
  String normalized;
  if (lastDot >= 0 && lastComma >= 0) {
    final decimal = lastDot > lastComma ? '.' : ',';
    final group = decimal == '.' ? ',' : '.';
    normalized = s.replaceAll(group, '');
    normalized =
        '${normalized.substring(0, normalized.lastIndexOf(decimal))}'
        '.${normalized.substring(normalized.lastIndexOf(decimal) + 1)}';
  } else if (lastDot >= 0 || lastComma >= 0) {
    final separator = lastDot >= 0 ? '.' : ',';
    final parts = s.split(separator);
    final isGrouping = parts.length > 2 || parts.last.length == 3;
    normalized =
        isGrouping ? parts.join() : '${parts.first}.${parts.skip(1).join()}';
  } else {
    normalized = s;
  }

  final value = double.tryParse(normalized);
  // Out-of-range values are rejected rather than converted: rupeesToMinor
  // would overflow the 64-bit minor-unit representation. The caller counts
  // these as skipped rows.
  if (value == null || !isAmountInRange(value)) return null;
  return negative ? -value : value;
}
