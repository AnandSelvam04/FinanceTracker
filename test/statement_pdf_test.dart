import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/services/statement_pdf.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.documentsPath);
  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pdf_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async => tempDir.delete(recursive: true));

  test('builds a valid, non-empty PDF for a period', () async {
    final txns = [
      Expense(
        description: 'Groceries',
        amount: 250,
        date: DateTime(2026, 6, 3),
        category: 'Food',
        paymentMode: 'UPI',
      ),
      Expense(
        description: 'Salary',
        amount: 40000,
        date: DateTime(2026, 6, 1),
        category: 'Salary',
        paymentMode: 'Other',
        type: DbConstants.txIncome,
      ),
    ];

    final file = await StatementPdf.build(
      title: 'Finance Tracker Statement',
      periodLabel: '2026-06',
      transactions: txns,
    );

    final bytes = await file.readAsBytes();
    expect(bytes.length, greaterThan(1000));
    // PDF files start with the "%PDF" magic bytes.
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(file.path, endsWith('statement_2026_06.pdf'));
  });
}
