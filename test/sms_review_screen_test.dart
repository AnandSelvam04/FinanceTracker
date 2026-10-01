import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/account.dart';
import 'package:finance_tracker/providers/account_provider.dart';
import 'package:finance_tracker/providers/expense_provider.dart';
import 'package:finance_tracker/providers/investment_provider.dart';
import 'package:finance_tracker/providers/recurring_provider.dart';
import 'package:finance_tracker/screens/sms_review_screen.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/services/sms_service.dart';

/// Renders the review queue from a stand-in inbox, so the notices and fields
/// added for refunds, card bill payments, foreign charges and shared last-4
/// digits are exercised on a real screen. Database work runs inside
/// `tester.runAsync` — see widget_flows_test.dart for why.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'sms_review_screen_test.db';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DBService().clearAll();
    SmsService.enabled = true;
  });

  tearDown(() {
    SmsService.inboxOverride = null;
    SmsService.enabled = false;
  });

  testWidgets('shows the new notices and fields for each kind of alert',
      (tester) async {
    final now = DateTime.now();
    RawSms sms(String body, int minutesAgo) => RawSms(
        sender: 'VM-HDFCBK',
        body: body,
        receivedAt: now.subtract(Duration(minutes: minutesAgo)));
    SmsService.inboxOverride = () async => [
          sms('Payment of Rs.15,000 received on your Card XX5678', 1),
          sms('Refund of Rs.500 credited to your Card XX5678 from AMAZON', 2),
          sms('USD 12.99 spent on Credit Card XX5678 at NETFLIX', 3),
          sms('Rs.499 debited from A/c XX1111 by UPI to ZOMATO', 4),
        ];

    final accounts = (await tester.runAsync(() async {
      await DBService().insertAccount(
          Account(name: 'HDFC Savings', type: 'bank', last4: '4821'));
      await DBService().insertAccount(
          Account(name: 'HDFC Card', type: 'credit_card', last4: '5678'));
      await DBService()
          .insertAccount(Account(name: 'Wallet A', type: 'upi', last4: '1111'));
      await DBService()
          .insertAccount(Account(name: 'Wallet B', type: 'upi', last4: '1111'));
      final a = AccountProvider();
      await a.fetchAccounts();
      return a;
    }))!;

    await tester.binding.setSurfaceSize(const Size(360, 3000));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountProvider>.value(value: accounts),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
        ChangeNotifierProvider(create: (_) => InvestmentProvider()),
        ChangeNotifierProvider(create: (_) => RecurringProvider()),
      ],
      child: const MaterialApp(home: SmsReviewScreen()),
    ));
    // The scan runs after the first frame and awaits the database; let the
    // real event loop deliver each reply, pumping in between.
    for (var i = 0; i < 20 && find.byType(Card).evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    expect(find.textContaining('credit card bill payment'), findsOneWidget);
    expect(find.text('Pick the account you paid from'), findsOneWidget);
    expect(find.textContaining('A refund'), findsOneWidget);
    expect(find.textContaining(r'Charged in $'), findsOneWidget);
    expect(find.text('Amount in ₹'), findsOneWidget);
    expect(find.text('2 accounts end in ••1111 — pick one'), findsOneWidget);
    expect(find.text('Category guessed from the merchant name.'),
        findsWidgets);
    expect(find.text('Payment mode'), findsWidgets);
    expect(find.text('Always ignore'), findsNWidgets(3));
    // The foreign charge starts unticked; the rest are ready to import.
    expect(find.text('Import 3 selected'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.binding.setSurfaceSize(null);
  }, timeout: const Timeout(Duration(seconds: 45)));
}
