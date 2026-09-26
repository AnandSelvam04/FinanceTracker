import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_tracker/main.dart';
import 'package:finance_tracker/services/auth_service.dart';

/// Stands in for the biometric prompt: answers with whatever [allow] holds.
class _FakeAuth extends AuthService {
  bool allow = true;
  int prompts = 0;

  @override
  Future<bool> canAuthenticate() async => true;

  @override
  Future<bool> authenticate() async {
    prompts++;
    return allow;
  }
}

void main() {
  late _FakeAuth auth;

  Widget app({bool enabled = true}) => MaterialApp(
        builder: (context, navigator) => AuthGate(
          enabled: enabled,
          lockAfter: Duration.zero,
          authService: auth,
          child: navigator!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        const Scaffold(body: Text('Account balances')),
                  ),
                ),
                child: const Text('Open accounts'),
              ),
            ),
          ),
        ),
      );

  Future<void> backgroundAndResume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  setUp(() => auth = _FakeAuth());

  testWidgets('does not build the app until the first unlock', (tester) async {
    auth.allow = false;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Finance Tracker is locked'), findsOneWidget);
    expect(find.text('Open accounts', skipOffstage: false), findsNothing);
  });

  testWidgets('a re-lock hides screens pushed on top of home', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open accounts'));
    await tester.pumpAndSettle();
    expect(find.text('Account balances'), findsOneWidget);

    auth.allow = false;
    await backgroundAndResume(tester);

    expect(auth.prompts, 2);
    expect(find.text('Finance Tracker is locked'), findsOneWidget);
    expect(find.text('Account balances'), findsNothing);
  });

  testWidgets('unlocking returns to the screen that was open', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open accounts'));
    await tester.pumpAndSettle();

    auth.allow = false;
    await backgroundAndResume(tester);
    expect(find.text('Account balances'), findsNothing);

    auth.allow = true;
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('Finance Tracker is locked'), findsNothing);
    expect(find.text('Account balances'), findsOneWidget);
  });

  testWidgets('turning the lock on takes effect without a restart',
      (tester) async {
    await tester.pumpWidget(app(enabled: false));
    await tester.pumpAndSettle();
    expect(auth.prompts, 0);
    expect(find.text('Open accounts'), findsOneWidget);

    // Switched on in the More tab: no prompt while the user is right there...
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(auth.prompts, 0);
    expect(find.text('Open accounts'), findsOneWidget);

    // ...but the next trip to the background locks.
    auth.allow = false;
    await backgroundAndResume(tester);
    expect(auth.prompts, 1);
    expect(find.text('Finance Tracker is locked'), findsOneWidget);
  });

  testWidgets('turning the lock off stops re-locking', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(enabled: false));
    await tester.pumpAndSettle();

    auth.allow = false;
    await backgroundAndResume(tester);
    expect(auth.prompts, 1); // only the launch prompt
    expect(find.text('Open accounts'), findsOneWidget);
  });
}
