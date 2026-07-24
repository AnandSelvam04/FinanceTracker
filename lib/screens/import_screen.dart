import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/account_provider.dart';
import '../providers/expense_provider.dart';
import '../services/csv_import.dart';
import '../services/db_service.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';

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

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final content = await File(path).readAsString();
    final rows = const CsvToListConverter(shouldParseNumbers: false)
        .convert(content);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _dateCol = 0;
      _descCol = rows.isNotEmpty && rows.first.length > 1 ? 1 : 0;
      _amountCol = rows.isNotEmpty && rows.first.length > 2 ? 2 : 0;
      _categoryCol = null;
      _typeCol = null;
    });
  }

  List<String> _columnNames(AppLocalizations l) {
    final rows = _rows;
    if (rows == null || rows.isEmpty) return [];
    final width = rows.first.length;
    if (_hasHeader) {
      return [
        for (var i = 0; i < width; i++)
          rows.first[i]?.toString().trim().isNotEmpty == true
              ? rows.first[i].toString()
              : l.columnN(i + 1)
      ];
    }
    return [for (var i = 0; i < width; i++) l.columnN(i + 1)];
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
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final expenseProvider = context.read<ExpenseProvider>();
    final accountProvider = context.read<AccountProvider>();
    final result = parseCsvExpenses(rows, hasHeader: _hasHeader, mapping: _mapping);
    if (result.expenses.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.noValidRows)),
      );
      return;
    }
    setState(() => _importing = true);
    try {
      for (final e in result.expenses) {
        await DBService().insertExpense(e);
      }
      await expenseProvider.reloadLoadedYears();
      await accountProvider.refreshBalances();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content:
            Text(l.importedSkipped(result.expenses.length, result.skipped)),
      ));
      Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(l.errorWithDetails('$e'))));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final rows = _rows;
    final columns = _columnNames(l);

    return Scaffold(
      appBar: AppBar(title: Text(l.importFromCsv)),
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
                      l.pickCsvHint,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: Text(l.chooseCsvFile),
                    onPressed: _pickFile,
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.firstRowHeader),
                  value: _hasHeader,
                  onChanged: (v) => setState(() => _hasHeader = v),
                ),
                const Divider(),
                _mapDropdown(l.dateColumn, _dateCol, columns,
                    (v) => setState(() => _dateCol = v!)),
                _mapDropdown(l.descriptionColumn, _descCol, columns,
                    (v) => setState(() => _descCol = v!)),
                _mapDropdown(l.amountColumn, _amountCol, columns,
                    (v) => setState(() => _amountCol = v!)),
                _mapDropdownOptional(l.categoryColumnOptional, _categoryCol,
                    columns, (v) => setState(() => _categoryCol = v), l),
                _mapDropdownOptional(l.typeColumnOptional, _typeCol,
                    columns, (v) => setState(() => _typeCol = v), l),
                if (_typeCol == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: DropdownButtonFormField<String>(
                      initialValue: _defaultType,
                      decoration: InputDecoration(
                          labelText: l.importAllRowsAs),
                      items: [
                        DropdownMenuItem(
                            value: DbConstants.txExpense,
                            child: Text(l.expense)),
                        DropdownMenuItem(
                            value: DbConstants.txIncome, child: Text(l.income)),
                      ],
                      onChanged: (v) =>
                          setState(() => _defaultType = v ?? _defaultType),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(l.preview,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _preview(rows, l),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: _importing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(l.importAction),
                  onPressed: _importing ? null : _import,
                ),
                TextButton(
                  onPressed: () => setState(() => _rows = null),
                  child: Text(l.chooseDifferentFile),
                ),
              ],
            ),
    );
  }

  Widget _preview(List<List<dynamic>> rows, AppLocalizations l) {
    final result = parseCsvExpenses(rows, hasHeader: _hasHeader, mapping: _mapping);
    final sample = result.expenses.take(5).toList();
    if (sample.isEmpty) {
      return Text(l.noValidRowsMapping);
    }
    return Column(
      children: [
        for (final e in sample)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title:
                Text(e.description.isEmpty ? l.noDescription : e.description),
            subtitle: Text(
                '${e.category} · ${e.date.year}-${e.date.month.toString().padLeft(2, '0')}-${e.date.day.toString().padLeft(2, '0')} · ${e.type}'),
            trailing: Text(formatMoney(e.amount)),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            l.willImportSkip(result.expenses.length, result.skipped),
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
      ValueChanged<int?> onChanged, AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DropdownButtonFormField<int?>(
        initialValue: (value != null && value < columns.length) ? value : null,
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem<int?>(value: null, child: Text(l.none)),
          for (var i = 0; i < columns.length; i++)
            DropdownMenuItem(value: i, child: Text(columns[i])),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
