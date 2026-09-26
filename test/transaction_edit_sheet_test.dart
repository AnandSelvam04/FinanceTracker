import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/providers/settings_provider.dart';
import 'package:finance_tracker/providers/template_provider.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:finance_tracker/widgets/transaction_edit_sheet.dart';

/// The shared edit sheet used by the Transactions list and the dashboard.
///
/// Database work runs inside `tester.runAsync` (see widget_flows_test.dart for
/// why: sqflite_common_ffi's isolate replies never land in the fake-async
/// zone), and taps that save are followed by a real-time [settle].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'transaction_edit_sheet_test.db';

  final day = DateTime(DateTime.now().year, 1, 15);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DBService().clearAll();
  });

  /// Seeds [row], loads it into fresh providers, and pumps a page whose
  /// button opens the edit sheet for it.
  Future<Expense> pumpEditor(WidgetTester tester, Expense row) async {
    final (expenses, accounts, seeded) = (await tester.runAsync(() async {
      await DBService().insertExpense(row);
      final e = ExpenseProvider();
      await e.ensureYearLoaded(day.year);
      final a = AccountProvider();
      await a.fetchAccounts();
      return (e, a, e.expenses.single);
    }))!;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ExpenseProvider>.value(value: expenses),
        ChangeNotifierProvider<AccountProvider>.value(value: accounts),
        // For the Add screen that Duplicate opens.
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => TemplateProvider()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => editTransactionSheet(context, seeded),
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    return seeded;
  }

  /// Lets database calls started by a tap finish, then renders the result.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
  }

  Future<List<Expense>> dbRows(WidgetTester tester) async =>
      (await tester.runAsync(() => DBService().getExpenses()))!;

  testWidgets('opens for an SMS-imported income with no payment mode',
      (tester) async {
    await pumpEditor(
      tester,
      Expense(
        description: 'Salary',
        amount: 5000000,
        date: day,
        category: 'Salary',
        paymentMode: '', // what the SMS importer stores for income
        type: DbConstants.txIncome,
        sourceRef: 'sms:1',
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Edit Income'), findsOneWidget);
  });

  testWidgets('saving an edit keeps the SMS import link', (tester) async {
    await pumpEditor(
      tester,
      Expense(
        description: 'Swiggy',
        amount: 45000,
        date: day,
        category: 'Food',
        paymentMode: 'Other',
        sourceRef: 'sms:42',
      ),
    );

    // Typing raises the keyboard; saving dismisses it while the sheet is
    // still animating closed, which rebuilds the fields. Their controllers
    // must still be alive then (they used to be disposed already).
    await tester.enterText(
        find.widgetWithText(TextField, 'Swiggy'), 'Swiggy dinner');
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(tester.takeException(), isNull);
    final row = (await dbRows(tester)).single;
    expect(row.description, 'Swiggy dinner');
    expect(row.sourceRef, 'sms:42');
  });

  testWidgets('Split from the edit sheet saves the parts', (tester) async {
    await pumpEditor(
      tester,
      Expense(
        description: 'Big bazaar',
        amount: 100000, // 1000.00
        date: day,
        category: 'Groceries',
        paymentMode: 'Debit Card',
      ),
    );

    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();
    expect(find.text('Split transaction'), findsOneWidget);

    final amounts = find.widgetWithText(TextField, 'Amount');
    final categories = find.widgetWithText(TextField, 'Category');
    await tester.enterText(amounts.at(0), '700');
    await tester.enterText(categories.at(1), 'Gifts');
    await tester.enterText(amounts.at(1), '300');
    await tester.pump();
    await tester.tap(find.text('Save split'));
    await settle(tester);

    final rows = await dbRows(tester);
    expect(
      {for (final r in rows) r.category: r.amount},
      {'Groceries': 70000, 'Gifts': 30000},
    );
    expect(find.text('Split into 2 transactions.'), findsOneWidget);
  });

  testWidgets('Duplicate opens Add pre-filled and dated today', (tester) async {
    final original = await pumpEditor(
      tester,
      Expense(
        description: 'Swiggy',
        amount: 45000,
        date: day,
        category: 'Food',
        paymentMode: 'UPI',
        sourceRef: 'sms:42',
      ),
    );

    await tester.tap(find.text('Duplicate'));
    await settle(tester);

    expect(find.text('Duplicate Expense'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Swiggy'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '450.00'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Food'), findsOneWidget);

    final add = find.widgetWithText(FilledButton, 'Add Expense');
    await tester.ensureVisible(add);
    await tester.tap(add);
    // Fixed pumps, not pumpAndSettle: the saving spinner animates until the
    // database write lands, so the tree never settles in between.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    final rows = await dbRows(tester);
    expect(rows.length, 2);
    final copy = rows.singleWhere((r) => r.id != original.id);
    expect(DateUtils.dateOnly(copy.date), DateUtils.dateOnly(DateTime.now()));
    expect(copy.description, 'Swiggy');
    expect(copy.amount, 45000);
    expect(copy.category, 'Food');
    expect(copy.paymentMode, 'UPI');
    // A copy is a new, hand-entered row: it must not claim the original's
    // SMS, or a rescan would treat the two as one.
    expect(copy.sourceRef, isNull);
  });
}
