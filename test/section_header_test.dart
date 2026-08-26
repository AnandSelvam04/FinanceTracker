import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/widgets/section_header.dart';

void main() {
  testWidgets('renders its label with the theme title style', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SectionHeader('Spending by category')),
    ));
    await tester.pump();

    expect(find.text('Spending by category'), findsOneWidget);
    // Uses the theme's titleMedium scale (not a hardcoded size), bolded.
    final text = tester.widget<Text>(find.text('Spending by category'));
    expect(text.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('honours a custom padding', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SectionHeader('General',
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4)),
      ),
    ));
    await tester.pump();

    final padding = tester.widget<Padding>(
      find.ancestor(of: find.text('General'), matching: find.byType(Padding)).first,
    );
    expect(padding.padding, const EdgeInsets.fromLTRB(16, 16, 16, 4));
  });
}
