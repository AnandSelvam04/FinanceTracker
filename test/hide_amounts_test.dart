import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_tracker/providers/settings_provider.dart';
import 'package:finance_tracker/utils/currency_format.dart';

/// A const widget, like many amount displays in the app: it only rebuilds
/// when something marks it dirty.
class _Amount extends StatelessWidget {
  const _Amount();
  @override
  Widget build(BuildContext context) => Text(formatMoney(250000));
}

void main() {
  tearDown(() => CurrencyFormat.hideAmounts = false);

  testWidgets('toggling hides amounts everywhere at once, and persists',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.load();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: settings,
      child: const MaterialApp(home: Scaffold(body: _Amount())),
    ));
    expect(find.text('₹2,500.00'), findsOneWidget);

    await settings.setHideAmounts(true);
    await tester.pump();
    expect(find.text('₹ •••••'), findsOneWidget);

    final reloaded = SettingsProvider();
    await reloaded.load();
    expect(reloaded.hideAmounts, isTrue);

    await settings.setHideAmounts(false);
    await tester.pump();
    expect(find.text('₹2,500.00'), findsOneWidget);
  });
}
