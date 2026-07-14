import '../models/expense.dart';
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

  for (final row in data) {
    if (row.every((c) => (c?.toString().trim() ?? '').isEmpty)) continue;
    final date = tryParseCsvDate(cell(row, mapping.dateCol));
    final amount = tryParseCsvAmount(cell(row, mapping.amountCol));
    if (date == null || amount == null) {
      skipped++;
      continue;
    }
    final category = cell(row, mapping.categoryCol);
    final type = _normalizeType(cell(row, mapping.typeCol), mapping.defaultType);
    expenses.add(Expense(
      description: cell(row, mapping.descriptionCol),
      amount: amount,
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

/// Strips currency symbols, thousands separators, and sign, returning the
/// absolute amount.
double? tryParseCsvAmount(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
  if (cleaned.isEmpty || cleaned == '-' || cleaned == '.') return null;
  final value = double.tryParse(cleaned);
  return value?.abs();
}
