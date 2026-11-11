import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/providers/budget_provider.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/providers/recurring_provider.dart';
import 'package:finance_tracker/providers/template_provider.dart';
import 'package:finance_tracker/screens/categories_screen.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/category_icons.dart';
import 'package:finance_tracker/utils/category_store.dart';
import 'package:finance_tracker/utils/db_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'categories_screen_test.db';

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> pumpScreen(WidgetTester tester,
      {List<String> spent = const []}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      await CategoryStore.instance.load();
      await DBService().clearAll();
      for (final c in spent) {
        await DBService().insertExpense(Expense(
            description: c,
            amount: 1000,
            date: DateTime.now(),
            category: c,
            paymentMode: 'UPI'));
      }
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
        ChangeNotifierProvider(create: (_) => AccountProvider()),
        ChangeNotifierProvider(create: (_) => BudgetProvider()),
        ChangeNotifierProvider(create: (_) => RecurringProvider()),
        ChangeNotifierProvider(create: (_) => TemplateProvider()),
      ],
      child: const MaterialApp(home: CategoriesScreen()),
    ));
    await settle(tester);
  }

  Future<List<String>> categoriesInDb(WidgetTester tester) async {
    final usage = (await tester
        .runAsync(() => DBService().categoryUsage(DbConstants.txExpense)))!;
    return [for (final u in usage) u.category];
  }

  testWidgets('lists unused built-in categories next to the ones in use',
      (tester) async {
    await pumpScreen(tester, spent: ['Groceries']);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('1 transaction'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Not used yet'), findsWidgets);
  });

  testWidgets('adds a category with an icon', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('New category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Rent');
    await tester.pump();
    await tester.ensureVisible(find.byTooltip('home'));
    await tester.pump();
    await tester.tap(find.byTooltip('home'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle(tester);

    expect(find.text('Rent'), findsOneWidget);
    expect(CategoryStore.instance.offered(DbConstants.txExpense).first, 'Rent');
    expect(categoryIcon('Rent'), Icons.home);
  });

  testWidgets('a new category cannot take an existing name', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('New category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'food');
    await tester.pump();
    expect(find.text('"Food" already exists.'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'))
            .onPressed,
        isNull);
  });

  testWidgets('removing an unused category takes it off the list',
      (tester) async {
    await pumpScreen(tester);
    await tester.ensureVisible(find.byTooltip('Remove Education'));
    await tester.pump();
    await tester.tap(find.byTooltip('Remove Education'));
    await settle(tester);
    expect(find.text('Education'), findsNothing);
    expect(CategoryStore.instance.offered(DbConstants.txExpense),
        isNot(contains('Education')));
  });

  testWidgets('removing a category in use moves its transactions',
      (tester) async {
    await pumpScreen(tester, spent: ['Grocery', 'Groceries']);
    await tester.tap(find.byTooltip('Remove Grocery'));
    await tester.pumpAndSettle();
    expect(find.text('Remove "Grocery"?'), findsOneWidget);
    // Nothing happens until a destination is picked.
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Move and remove'))
            .onPressed,
        isNull);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Groceries'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Move and remove'));
    await settle(tester);

    expect(await categoriesInDb(tester), ['Groceries']);
    expect(find.text('2 transactions'), findsOneWidget);
  });

  testWidgets('renaming keeps the transactions and the chosen colour',
      (tester) async {
    await pumpScreen(tester, spent: ['Rent']);
    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Housing');
    await tester.pump();
    await tester.ensureVisible(find.byTooltip('home'));
    await tester.pump();
    await tester.tap(find.byTooltip('home'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);

    expect(await categoriesInDb(tester), ['Housing']);
    expect(categoryIcon('Housing'), Icons.home);
    expect(find.text('Rent'), findsNothing);
  });
}
