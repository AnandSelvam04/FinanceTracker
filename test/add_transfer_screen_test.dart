import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/providers/settings_provider.dart';
import 'package:finance_tracker/screens/add_transfer_screen.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';

/// The transfer screen opened pre-filled: to pay a card bill from its
/// reminder, or to duplicate an earlier transfer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'add_transfer_screen_test.db';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DBService().clearAll();
  });

  /// Seeds a bank and a card, then pumps the screen [build] makes with
  /// their ids.
  Future<void> pump(
      WidgetTester tester, AddTransferScreen Function(int bank, int card) build,
      {bool bankIsDefault = false}) async {
    final (accounts, settings, bank, card) = (await tester.runAsync(() async {
      final bank =
          await DBService().insertAccount(Account(name: 'HDFC', type: 'bank'));
      final card = await DBService()
          .insertAccount(Account(name: 'Amex', type: 'credit_card'));
      final a = AccountProvider();
      await a.fetchAccounts();
      final s = SettingsProvider();
      await s.load();
      if (bankIsDefault) await s.setDefaultAccountId(bank);
      return (a, s, bank, card);
    }))!;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountProvider>.value(value: accounts),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
      ],
      child: MaterialApp(home: build(bank, card)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Pay opens with the card, the amount due and the default account',
      (tester) async {
    await pump(
      tester,
      (bank, card) =>
          AddTransferScreen(initialToAccountId: card, initialAmount: 1234500),
      bankIsDefault: true,
    );

    expect(find.widgetWithText(TextFormField, '12345.00'), findsOneWidget);
    expect(find.text('Amex'), findsOneWidget);
    expect(find.text('HDFC'), findsOneWidget);
  });

  testWidgets('Duplicate copies the accounts, amount and note', (tester) async {
    await pump(
      tester,
      (bank, card) => AddTransferScreen(
        duplicateOf: Expense(
          description: 'Card bill',
          amount: 500000,
          date: DateTime(2026, 1, 5),
          category: 'Transfer',
          paymentMode: 'Other',
          type: DbConstants.txTransfer,
          accountId: bank,
          toAccountId: card,
        ),
      ),
    );

    expect(find.text('Duplicate transfer'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '5000.00'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Card bill'), findsOneWidget);
    expect(find.text('HDFC'), findsOneWidget);
    expect(find.text('Amex'), findsOneWidget);
  });
}
