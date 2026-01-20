import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    // Initialize sqflite for widget tests
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('App loads and shows Finance Tracker',
      (WidgetTester tester) async {
    await tester.pumpWidget(const FinanceTrackerApp(seenOnboarding: true));
    await tester.pumpAndSettle();
    expect(find.text('Finance Tracker'), findsOneWidget);
  });
}
