import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_tracker/providers/settings_provider.dart';
import 'package:finance_tracker/screens/customize_home_screen.dart';
import 'package:finance_tracker/screens/more_screen.dart';
import 'package:finance_tracker/utils/app_theme.dart';
import 'package:finance_tracker/utils/dashboard_layout.dart';
import 'package:finance_tracker/widgets/amount_calculator_bar.dart';
import 'package:finance_tracker/widgets/celebration.dart';
import 'package:finance_tracker/widgets/swipe_actions.dart';

Future<SettingsProvider> loadSettings(
    [Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final settings = SettingsProvider();
  await settings.load();
  return settings;
}

void main() {
  group('AmountCalculatorBar', () {
    testWidgets('inserts an operator and replaces the sum with its answer',
        (tester) async {
      final controller = TextEditingController(text: '250');
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AmountCalculatorBar(controller: controller)),
      ));
      expect(find.text('Add up or split here'), findsOneWidget);

      await tester.tap(find.text('+'));
      await tester.pump();
      expect(controller.text, '250+');
      expect(find.text('Finish the sum'), findsOneWidget);

      controller.text = '250+80';
      await tester.pump();
      await tester.tap(find.text('= 330.00'));
      await tester.pump();
      expect(controller.text, '330.00');
      expect(find.text('Add up or split here'), findsOneWidget);
    });

    testWidgets('puts the operator where the cursor is', (tester) async {
      final controller = TextEditingController.fromValue(const TextEditingValue(
          text: '1200', selection: TextSelection.collapsed(offset: 2)));
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AmountCalculatorBar(controller: controller)),
      ));
      await tester.tap(find.text('÷'));
      await tester.pump();
      expect(controller.text, '12÷00');
      expect(controller.selection.baseOffset, 3);
    });
  });

  group('SwipeActions', () {
    Future<List<String>> pump(WidgetTester tester) async {
      final calls = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SwipeActions(
            key: const ValueKey('row'),
            onEdit: () => calls.add('edit'),
            onDelete: () => calls.add('delete'),
            child: const ListTile(title: Text('Groceries')),
          ),
        ),
      ));
      return calls;
    }

    testWidgets('left deletes, right edits, and the row stays put',
        (tester) async {
      final calls = await pump(tester);
      await tester.drag(find.text('Groceries'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(calls, ['delete']);
      expect(find.text('Groceries'), findsOneWidget);

      await tester.drag(find.text('Groceries'), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(calls, ['delete', 'edit']);
      expect(find.text('Groceries'), findsOneWidget);
    });

    testWidgets('offers both actions to screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      final labels = tester
          .getSemantics(find.byType(Dismissible))
          .getSemanticsData()
          .customSemanticsActionIds!
          .map((id) => CustomSemanticsAction.getAction(id)!.label);
      expect(labels, containsAll(['Edit', 'Delete']));
      handle.dispose();
    });
  });

  group('More', () {
    Future<void> pump(WidgetTester tester) async {
      final settings = await loadSettings();
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: settings,
        child: const MaterialApp(home: MoreScreen()),
      ));
      await tester.pump();
    }

    testWidgets('lists Cards and Customise home', (tester) async {
      await pump(tester);
      expect(find.text('Cards'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Customise home'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Customise home'), findsOneWidget);
    });

    testWidgets('search finds screens, settings, and says when nothing matches',
        (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'export');
      await tester.pump();
      expect(find.text('Backup & Export'), findsOneWidget);
      expect(find.text('Reports'), findsOneWidget);
      expect(find.text('Accounts'), findsNothing);

      // A setting, found by a word that is not in its name.
      await tester.enterText(find.byType(TextField), 'fingerprint');
      await tester.pump();
      expect(find.text('App lock'), findsOneWidget);
      expect(find.text('In Settings'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pump();
      expect(find.text('Nothing called "zzzz"'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.text('Accounts'), findsOneWidget);
    });
  });

  group('Customise home', () {
    testWidgets('hides a section, keeps the figures, and resets',
        (tester) async {
      final settings = await loadSettings();
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: settings,
        child: const MaterialApp(home: CustomizeHomeScreen()),
      ));
      // One switch per section, less the one that is always shown.
      expect(find.byType(Switch),
          findsNWidgets(DashboardLayout.defaultOrder.length - 1));
      expect(find.text('Always shown'), findsOneWidget);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(settings.dashboardHidden, {DashboardLayout.netWorth});
      expect(settings.dashboardSections,
          isNot(contains(DashboardLayout.netWorth)));

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(settings.dashboardHidden, isEmpty);
    });

    testWidgets('allows four shortcuts and no more', (tester) async {
      final settings = await loadSettings();
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: settings,
        child: const MaterialApp(home: CustomizeHomeScreen()),
      ));
      // SMS reading is off, so Import SMS is not offered.
      expect(find.widgetWithText(FilterChip, 'Import SMS'), findsNothing);

      Future<void> pick(String label) async {
        final chip = find.widgetWithText(FilterChip, label);
        await tester.scrollUntilVisible(chip, 200,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(chip);
        await tester.pumpAndSettle();
      }

      await pick('Reports');
      expect(settings.homeShortcuts.length, 4);
      // Full: a fifth cannot be picked, but one can be dropped.
      await pick('Goals');
      expect(settings.homeShortcuts, isNot(contains(DashboardLayout.goals)));
      await pick('Cards');
      expect(settings.homeShortcuts, isNot(contains(DashboardLayout.cards)));
      await pick('Goals');
      expect(settings.homeShortcuts.last, DashboardLayout.goals);
    });
  });

  group('celebrate', () {
    testWidgets('shows the message with confetti, which clears itself',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => celebrate(context, 'Goal reached!'),
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.text('Goal reached!'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      final during = tester.widgetList(find.byType(IgnorePointer)).length;
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(tester.widgetList(find.byType(IgnorePointer)).length,
          lessThan(during));
    });

    testWidgets('skips the confetti under reduced motion', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => celebrate(context, 'Goal reached!'),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ));
      final before = tester.widgetList(find.byType(IgnorePointer)).length;
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.text('Goal reached!'), findsOneWidget);
      expect(tester.widgetList(find.byType(IgnorePointer)).length, before);
    });
  });

  test('true black paints the page black and keeps raised surfaces apart', () {
    final plain = AppTheme.dark();
    final black = AppTheme.dark(null, true);
    expect(plain.scaffoldBackgroundColor, isNot(Colors.black));
    expect(black.scaffoldBackgroundColor, Colors.black);
    expect(black.colorScheme.surfaceContainerLow, isNot(Colors.black));
    expect(black.colorScheme.surfaceContainerHigh,
        isNot(black.colorScheme.surfaceContainerLow));
    // Light mode is never affected.
    expect(AppTheme.light().scaffoldBackgroundColor, isNot(Colors.black));
  });
}
