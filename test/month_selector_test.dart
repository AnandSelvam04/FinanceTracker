import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/widgets/month_selector.dart';

void main() {
  Future<List<(int, int)>> pump(WidgetTester tester,
      {bool yearOnly = false}) async {
    final changes = <(int, int)>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MonthSelector(
          initialYear: 2026,
          initialMonth: 1,
          yearOnly: yearOnly,
          onChanged: (y, m) => changes.add((y, m)),
        ),
      ),
    ));
    return changes;
  }

  testWidgets('steps months across a year boundary', (tester) async {
    final changes = await pump(tester);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.tap(find.byTooltip('Next month'));
    await tester.tap(find.byTooltip('Next month'));
    expect(changes, [(2025, 12), (2026, 1), (2026, 2)]);
  });

  testWidgets('year-only mode steps and shows whole years', (tester) async {
    final changes = await pump(tester, yearOnly: true);
    expect(find.text('2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous year'));
    await tester.pump();
    expect(changes, [(2025, 1)]);
    expect(find.text('2025'), findsOneWidget);
  });
}
