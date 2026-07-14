import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/main.dart';
import 'package:finance_tracker/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    // Initialize sqflite for widget tests
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('App loads and shows Finance Tracker',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.load();
    await tester.pumpWidget(
        FinanceTrackerApp(settings: settings, seenOnboarding: true));
    await tester.pumpAndSettle();
    expect(find.text('Finance Tracker'), findsOneWidget);
  });
}
