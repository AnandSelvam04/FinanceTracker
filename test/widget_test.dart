import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/main.dart';
import 'package:finance_tracker/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    // Initialize sqflite for widget tests
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  // Isolate this file's database so concurrently running test files
  // can't clear each other's data (they all share one ffi process).
  DBService.dbNameOverride = 'widget_test.db';
  });

  testWidgets('App loads and shows Finance Tracker',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.load();
    await tester.pumpWidget(
        FinanceTrackerApp(settings: settings, seenOnboarding: true));
    // Not pumpAndSettle: the dashboard shows a CircularProgressIndicator
    // while the first year of transactions loads, and an indeterminate
    // spinner schedules frames forever, so pumpAndSettle never returns.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Finance Tracker'), findsOneWidget);
  });
}
