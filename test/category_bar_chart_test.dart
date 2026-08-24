import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/widgets/category_bar_chart.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pump();
  }

  testWidgets('renders a labelled bar per category with amount and share',
      (tester) async {
    await pump(
      tester,
      const CategoryBarChart(totals: {'Food': 30000, 'Bills': 10000}),
    );

    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Bills'), findsOneWidget);
    expect(find.text('₹300.00'), findsOneWidget);
    expect(find.text('₹100.00'), findsOneWidget);
    // 30000 / 40000 = 75%, 10000 / 40000 = 25%.
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
  });

  testWidgets('orders categories largest first', (tester) async {
    await pump(
      tester,
      const CategoryBarChart(totals: {'Bills': 10000, 'Food': 30000}),
    );

    // Food is larger, so its row sits above Bills regardless of map order.
    expect(tester.getCenter(find.text('Food')).dy,
        lessThan(tester.getCenter(find.text('Bills')).dy));
  });

  testWidgets('tapping a category reports it', (tester) async {
    String? tapped;
    await pump(
      tester,
      CategoryBarChart(
        totals: const {'Food': 30000, 'Bills': 10000},
        onCategoryTap: (c) => tapped = c,
      ),
    );

    await tester.tap(find.text('Food'));
    expect(tapped, 'Food');
  });

  testWidgets('zero and empty totals render nothing', (tester) async {
    await pump(tester, const CategoryBarChart(totals: {}));
    expect(find.byType(InkWell), findsNothing);

    await pump(tester, const CategoryBarChart(totals: {'Food': 0}));
    expect(find.text('Food'), findsNothing);
  });
}
