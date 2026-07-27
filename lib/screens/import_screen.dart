import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../services/csv_import.dart';
import '../services/db_service.dart';
import '../utils/app_logger.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';
import '../utils/insets.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  List<List<dynamic>>? _rows;
  bool _hasHeader = true;
  bool _importing = false;

  int _dateCol = 0;
  int _descCol = 1;
  int _amountCol = 2;
  int? _categoryCol;
  int? _typeCol;
  String _defaultType = DbConstants.txExpense;

  /// Largest CSV accepted. Reading and parsing both run on the UI isolate, so
  /// an unbounded file would lock the app up with no way to cancel.
  static const _maxCsvBytes = 10 * 1024 * 1024;

  Future<void> _pickFile() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    final path = result?.files.single.path;
    if (path == null) return;

    List<List<dynamic>> rows;
    try {
      final file = File(path);
      // Reading and parsing both happen on the UI isolate, so a huge file
      // would freeze the app with no way out. Refuse it up front instead.
      final length = await file.length();
      if (length > _maxCsvBytes) {
        messenger.showSnackBar(SnackBar(
          content: Text('That file is ${(length / (1024 * 1024)).toStringAsFixed(1)} MB. '
              'Please split it into files under '
              '${_maxCsvBytes ~/ (1024 * 1024)} MB.'),
        ));
        return;
      }
      // Not every export is UTF-8; a Latin-1 statement used to throw an
      // unhandled decoding error with no feedback at all.
      final content = await file.readAsString();
      rows =
          const CsvToListConverter(shouldParseNumbers: false).convert(content);
    } catch (e) {
      AppLogger.error('Could not read the selected CSV', e);
      messenger.showSnackBar(SnackBar(
        content: const Text(
            "Could not read that file. Make sure it's a UTF-8 CSV export."),
      ));
      return;
    }

    if (rows.isEmpty) {
      messenger.showSnackBar(
          SnackBar(content: const Text('That file has no rows.')));
      return;
    }
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _dateCol = 0;
      _descCol = rows.first.length > 1 ? 1 : 0;
      _amountCol = rows.first.length > 2 ? 2 : 0;
      _categoryCol = null;
      _typeCol = null;
    });
  }

  List<String> get _columnNames {
    final rows = _rows;
    if (rows == null || rows.isEmpty) return [];
    final width = rows.first.length;
    if (_hasHeader) {
      return [
        for (var i = 0; i < width; i++)
          rows.first[i]?.toString().trim().isNotEmpty == true
              ? rows.first[i].toString()
              : 'Column ${i + 1}'
      ];
    }
    return [for (var i = 0; i < width; i++) 'Column ${i + 1}'];
  }

  CsvColumnMapping get _mapping => CsvColumnMapping(
        dateCol: _dateCol,
        descriptionCol: _descCol,
        amountCol: _amountCol,
        categoryCol: _categoryCol,
        typeCol: _typeCol,
        defaultType: _defaultType,
      );

  Future<void> _import() async {
    final rows = _rows;
    if (rows == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final expenseProvider = context.read<ExpenseProvider>();
    final accountProvider = context.read<AccountProvider>();
    final result = parseCsvExpenses(rows, hasHeader: _hasHeader, mapping: _mapping);
    if (result.expenses.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: const Text('No valid rows to import.')),
      );
      return;
    }
    setState(() => _importing = true);
    try {
      // One transaction, so a failure part-way through leaves no half-imported
      // file behind for the user to untangle by hand.
      await DBService().insertExpenses(result.expenses);
      await expenseProvider.reloadLoadedYears();
      await accountProvider.refreshBalances();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content:
            Text('Imported ${result.expenses.length}, skipped ${result.skipped}'),
      ));
      Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final columns = _columnNames;

    return Scaffold(
      appBar: AppBar(title: const Text('Import from CSV')),
      body: rows == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.upload_file, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Pick a CSV file (e.g. a bank statement or an export from another app), then map its columns.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Choose CSV file'),
                    onPressed: _pickFile,
                  ),
                ],
              ),
            )
          : ListView(
              padding: scrollPadding(context),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('First row is a header'),
                  value: _hasHeader,
                  onChanged: (v) => setState(() => _hasHeader = v),
                ),
                const Divider(),
                _mapDropdown('Date column', _dateCol, columns,
                    (v) => setState(() => _dateCol = v!)),
                _mapDropdown('Description column', _descCol, columns,
                    (v) => setState(() => _descCol = v!)),
                _mapDropdown('Amount column', _amountCol, columns,
                    (v) => setState(() => _amountCol = v!)),
                _mapDropdownOptional('Category column (optional)', _categoryCol,
                    columns, (v) => setState(() => _categoryCol = v)),
                _mapDropdownOptional('Type column (optional)', _typeCol,
                    columns, (v) => setState(() => _typeCol = v)),
                if (_typeCol == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: DropdownButtonFormField<String>(
                      initialValue: _defaultType,
                      decoration: InputDecoration(
                          labelText: 'Import all rows as'),
                      items: [
                        DropdownMenuItem(
                            value: DbConstants.txExpense,
                            child: const Text('Expense')),
                        DropdownMenuItem(
                            value: DbConstants.txIncome, child: const Text('Income')),
                      ],
                      onChanged: (v) =>
                          setState(() => _defaultType = v ?? _defaultType),
                    ),
                  ),
                const SizedBox(height: 16),
                Text('Preview',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _preview(rows),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: _importing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const Text('Import'),
                  onPressed: _importing ? null : _import,
                ),
                TextButton(
                  onPressed: () => setState(() => _rows = null),
                  child: const Text('Choose a different file'),
                ),
              ],
            ),
    );
  }

  Widget _preview(List<List<dynamic>> rows) {
    final result = parseCsvExpenses(rows, hasHeader: _hasHeader, mapping: _mapping);
    final sample = result.expenses.take(5).toList();
    if (sample.isEmpty) {
      return const Text('No valid rows with the current mapping.');
    }
    return Column(
      children: [
        for (final e in sample)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title:
                Text(e.description.isEmpty ? '(no description)' : e.description),
            subtitle: Text(
                '${e.category} · ${e.date.year}-${e.date.month.toString().padLeft(2, '0')}-${e.date.day.toString().padLeft(2, '0')} · ${e.type}'),
            trailing: Text(formatMoney(e.amount)),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Will import ${result.expenses.length}, skip ${result.skipped}.',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _mapDropdown(String label, int value, List<String> columns,
      ValueChanged<int?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DropdownButtonFormField<int>(
        initialValue: value < columns.length ? value : null,
        decoration: InputDecoration(labelText: label),
        items: [
          for (var i = 0; i < columns.length; i++)
            DropdownMenuItem(value: i, child: Text(columns[i])),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _mapDropdownOptional(String label, int? value, List<String> columns,
      ValueChanged<int?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DropdownButtonFormField<int?>(
        initialValue: (value != null && value < columns.length) ? value : null,
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem<int?>(value: null, child: const Text('None')),
          for (var i = 0; i < columns.length; i++)
            DropdownMenuItem(value: i, child: Text(columns[i])),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
