import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/category_rule.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/providers/settings_provider.dart';
import 'package:finance_tracker/providers/template_provider.dart';
import 'package:finance_tracker/screens/add_expense_screen.dart';
import 'package:finance_tracker/screens/category_rules_screen.dart';
import 'package:finance_tracker/services/category_rules.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';
import 'package:finance_tracker/widgets/transaction_edit_sheet.dart';

/// The auto-categorise screens. Database calls run inside `tester.runAsync`
/// (see widget_flows_test.dart for why).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'category_rules_screen_test.db';

  const testTimeout = Timeout(Duration(seconds: 45));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CategoryRuleStore.instance.load();
    await DBService().clearAll();
  });

  /// Lets database work started by the screen land, pumping between waits,
  /// until [until] finds something (or a few rounds when not given).
  Future<void> settle(WidgetTester tester, {Finder? until}) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
      if (until == null ? i >= 4 : until.evaluate().isNotEmpty) return;
    }
  }

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final (accounts, expenses) = (await tester.runAsync(() async {
      final a = AccountProvider();
      await a.fetchAccounts();
      return (a, ExpenseProvider());
    }))!;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountProvider>.value(value: accounts),
        ChangeNotifierProvider<ExpenseProvider>.value(value: expenses),
        ChangeNotifierProvider(create: (_) => TemplateProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(home: screen),
    ));
    await settle(tester);
  }

  bool selected(WidgetTester tester, String label) => tester
      .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
      .selected;

  testWidgets('Add expense files the category from a rule as you type',
      (tester) async {
    await CategoryRuleStore.instance.add(CategoryRule(
        id: 'z', pattern: 'zomato', category: 'Food', tag: 'eatingout'));
    await pump(tester, const AddExpenseScreen());

    final description =
        find.widgetWithText(TextFormField, 'Description (optional)');
    await tester.enterText(description, 'Zomato dinner');
    await tester.pump();
    expect(selected(tester, 'Food'), isTrue);
    expect(find.textContaining('Set by your rule'), findsOneWidget);
    expect(find.textContaining('#eatingout'), findsOneWidget);

    // No longer a match: the rule takes back the category it set.
    await tester.enterText(description, 'Dinner');
    await tester.pump();
    expect(selected(tester, 'Food'), isFalse);
    expect(find.textContaining('Set by your rule'), findsNothing);

    // A category picked by hand is never overridden.
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Shopping'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Shopping'));
    await tester.pump();
    await tester.enterText(description, 'Zomato gift card');
    await tester.pump();
    expect(selected(tester, 'Shopping'), isTrue);
    expect(selected(tester, 'Food'), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: testTimeout);

  testWidgets('a new rule is created and tidies past transactions',
      (tester) async {
    final id = (await tester.runAsync(() async {
      final id = await DBService().insertExpense(Expense(
        description: 'UPI-ZOMATO-ORDER',
        amount: 45000,
        date: DateTime(2026, 3, 1),
        category: 'Other',
        paymentMode: 'UPI',
        type: DbConstants.txExpense,
      ));
      await DBService().insertExpense(Expense(
        description: 'Uber',
        amount: 20000,
        date: DateTime(2026, 3, 2),
        category: 'Transport',
        paymentMode: 'UPI',
        type: DbConstants.txExpense,
      ));
      return id;
    }))!;
    await pump(tester, const CategoryRulesScreen());

    expect(find.text('No rules yet'), findsOneWidget);
    await tester.tap(find.text('Create a rule'));
    await settle(tester, until: find.text('New rule'));
    await settle(tester);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Text to look for'), 'zomato');
    await tester.pump();
    expect(find.textContaining('Matches 1 transaction'), findsOneWidget);
    expect(find.textContaining('Choose a category'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Food'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Food'));
    await tester.pump();
    expect(find.textContaining('1 would change'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Tag (optional)'), 'Eating Out');
    await tester.pump();

    await tester.tap(find.text('Create rule'));
    await settle(tester, until: find.text('Update 1 past transaction?'));
    expect(
        find.textContaining('UPI-ZOMATO-ORDER: Other → Food'), findsOneWidget);
    await tester.tap(find.text('Update'));
    await settle(tester, until: find.text('Updated 1 transaction'));

    final rule = CategoryRuleStore.instance.rules.single;
    expect(rule.category, 'Food');
    expect(rule.tag, 'eating-out');
    final saved = (await tester.runAsync(() => DBService().getExpenses()))!
        .firstWhere((e) => e.id == id);
    expect(saved.category, 'Food');
    expect(saved.note, '#eating-out');

    // Back on the list, the rule shows with what it files.
    await settle(tester, until: find.text('Contains "zomato"'));
    expect(find.text('Contains "zomato"'), findsOneWidget);
    expect(find.textContaining('Expense → Food · #eating-out'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: testTimeout);

  testWidgets('recategorising a row by hand offers to make it a rule',
      (tester) async {
    Expense tx(String category) => Expense(
        description: 'ZOMATO 88213',
        amount: 45000,
        date: DateTime(2026, 3, 1),
        category: category,
        paymentMode: 'UPI');
    await pump(tester, const Scaffold(body: SizedBox()));
    final context = tester.element(find.byType(SizedBox).last);
    void offer(String from, String to) => offerRuleFor(
        tx(from), tx(to), Navigator.of(context), ScaffoldMessenger.of(context));

    offer('Other', 'Other');
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);

    offer('Other', 'Food');
    await tester.pump();
    expect(find.text('Always file "ZOMATO 88213" under Food?'), findsOneWidget);
    // Let the snackbar finish sliding in, or the tap lands short of it.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Make a rule'));
    await settle(tester, until: find.text('New rule'));
    // Filled in from the row, without the bank's reference number.
    expect(
        tester
            .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Text to look for'))
            .controller!
            .text,
        'zomato');
    expect(selected(tester, 'Food'), isTrue);
    await settle(tester);

    // Not offered again once a rule already files it there.
    ScaffoldMessenger.of(context).clearSnackBars();
    await CategoryRuleStore.instance
        .add(CategoryRule(id: 'z', pattern: 'zomato', category: 'Food'));
    offer('Other', 'Food');
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: testTimeout);
}
