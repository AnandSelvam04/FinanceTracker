import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/providers/settings_provider.dart';
import 'package:finance_tracker/screens/onboarding_screen.dart';
import 'package:finance_tracker/services/db_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'onboarding_test.db';

  late SettingsProvider settings;
  late AccountProvider accounts;

  Future<void> pump(WidgetTester tester, VoidCallback onFinish) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      await DBService().clearAll();
      settings = SettingsProvider();
      await settings.load();
      accounts = AccountProvider();
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: accounts),
      ],
      child: MaterialApp(home: OnboardingScreen(onFinish: onFinish)),
    ));
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
  }

  testWidgets('sets the currency and creates the first account',
      (tester) async {
    var finished = false;
    await pump(tester, () => finished = true);

    await next(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '€'));
    await tester.pumpAndSettle();
    expect(settings.currencySymbol, '€');

    await next(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Account name'), 'Main bank');
    await tester.enterText(
        find.widgetWithText(TextField, 'Current balance (optional)'),
        '1500.50');

    await next(tester);
    await tester.tap(find.text('Find transactions in bank SMS'));
    await tester.pumpAndSettle();
    expect(settings.smsImportEnabled, isTrue);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Get started'));
      for (var i = 0; i < 20 && !finished; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    expect(finished, isTrue);
    expect(accounts.accounts, hasLength(1));
    final account = accounts.accounts.single;
    expect(account.name, 'Main bank');
    expect(account.type, 'bank');
    expect(account.openingBalance, 150050);
    expect(settings.defaultAccountId, account.id);
  });

  testWidgets('Skip leaves the defaults and adds no account', (tester) async {
    var finished = false;
    await pump(tester, () => finished = true);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(settings.currencySymbol, '₹');
    final rows = await tester.runAsync(() => DBService().getAccounts());
    expect(rows, isEmpty);
  });

  testWidgets('a balance that is not a number is not saved', (tester) async {
    var finished = false;
    await pump(tester, () => finished = true);
    await next(tester);
    await next(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Account name'), 'Wallet');
    await tester.enterText(
        find.widgetWithText(TextField, 'Current balance (optional)'), 'abc');
    await next(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Get started'));
    await tester.pumpAndSettle();
    expect(finished, isFalse);
    expect(find.textContaining('not a number'), findsOneWidget);
    // Back on the account step.
    expect(find.text('Your main account'), findsOneWidget);
  });
}
