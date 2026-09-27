import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:finance_tracker/models/investment.dart';
import 'package:finance_tracker/providers/investment_provider.dart';
import 'package:finance_tracker/providers/recurring_provider.dart';
import 'package:finance_tracker/screens/add_investment_screen.dart';

/// Duplicating an investment opens the Add screen filled from the original.
void main() {
  Future<void> pumpDuplicate(WidgetTester tester, Investment original) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => InvestmentProvider()),
        ChangeNotifierProvider(create: (_) => RecurringProvider()),
      ],
      child: MaterialApp(home: AddInvestmentScreen(duplicateOf: original)),
    ));
    await tester.pump();
  }

  String nameField(WidgetTester tester) => tester
      .widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Name (optional)'))
      .controller!
      .text;

  testWidgets('copies type, name, amount and direction', (tester) async {
    await pumpDuplicate(
      tester,
      Investment(
        name: 'Nifty 50',
        amount: -500000, // a ₹5,000 withdrawal
        date: DateTime(2026, 7, 10),
        type: 'Mutual Funds',
      ),
    );

    expect(find.text('Duplicate Investment'), findsOneWidget);
    expect(nameField(tester), 'Nifty 50');
    expect(find.widgetWithText(TextFormField, '5000.00'), findsOneWidget);
    expect(find.text('Record Withdrawal'), findsOneWidget);
    expect(find.text('Mutual Funds'), findsOneWidget);
  });

  testWidgets('drops an auto-generated name so it matches the new date',
      (tester) async {
    await pumpDuplicate(
      tester,
      Investment(
        name: 'Silver Jul 2026', // what a blank name was saved as
        amount: 200000,
        date: DateTime(2026, 7, 10),
        type: 'Silver',
      ),
    );

    expect(nameField(tester), isEmpty);
  });
}
