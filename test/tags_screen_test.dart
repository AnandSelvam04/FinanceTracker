import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/screens/tags_screen.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/currency_format.dart';
import 'package:finance_tracker/utils/db_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'tags_screen_test.db';

  Expense e(String description, int amount, DateTime date,
          {String? note, String category = 'Food'}) =>
      Expense(
          description: description,
          amount: amount,
          date: date,
          category: category,
          paymentMode: 'UPI',
          type: DbConstants.txExpense,
          note: note);

  Future<void> pumpTags(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
        ChangeNotifierProvider(create: (_) => AccountProvider()),
      ],
      child: const MaterialApp(home: TagsScreen()),
    ));
  }

  /// Lets the screen's database read finish and rebuild.
  Future<void> settle(WidgetTester tester, Finder until) async {
    for (var i = 0; i < 20 && until.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  tearDown(() async => DBService().clearAll());

  testWidgets('says how to tag when nothing is tagged', (tester) async {
    await tester.runAsync(() async {
      await DBService().clearAll();
      await DBService().insertExpense(e('Lunch', 20000, DateTime(2026, 3, 1)));
    });
    await pumpTags(tester);
    await settle(tester, find.text('No tags yet'));
    expect(tester.takeException(), isNull);
    expect(find.text('No tags yet'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('totals a tag across categories and years, and opens it',
      (tester) async {
    await tester.runAsync(() async {
      await DBService().clearAll();
      // Two years apart and in different categories: still one tag.
      await DBService().insertExpense(e(
          'Flight', 1000000, DateTime(2024, 12, 20),
          note: 'booked early #goa-trip', category: 'Travel'));
      await DBService().insertExpense(
          e('Beach shack', 250000, DateTime(2026, 1, 3), note: '#Goa-Trip'));
      await DBService().insertExpense(
          e('Groceries', 90000, DateTime(2026, 1, 4), note: 'weekly'));
    });
    await pumpTags(tester);
    await settle(tester, find.text('#goa-trip'));
    expect(tester.takeException(), isNull);

    expect(find.text('#goa-trip'), findsOneWidget);
    expect(find.text('2 transactions'), findsOneWidget);
    expect(find.text(formatMoney(1250000)), findsOneWidget);
    // Untagged spending stays out.
    expect(find.text('Groceries'), findsNothing);

    await tester.tap(find.text('#goa-trip'));
    // Not pumpAndSettle: the detail's spinner animates until its read lands.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester, find.text('Flight'));
    expect(find.text('Flight'), findsOneWidget);
    expect(find.text('Beach shack'), findsOneWidget);
    expect(find.text('Groceries'), findsNothing);
    expect(find.text('Spent ${formatMoney(1250000)}'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 45)));
}
