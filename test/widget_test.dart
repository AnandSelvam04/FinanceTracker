import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/main.dart';

void main() {
  testWidgets('App loads and shows placeholder', (WidgetTester tester) async {
    await tester.pumpWidget(const FinanceTrackerApp());
    expect(find.text('Finance Tracker'), findsNothing);
    expect(find.byType(Placeholder), findsOneWidget);
  });
}
