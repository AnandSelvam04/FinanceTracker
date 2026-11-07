import 'package:flutter_test/flutter_test.dart';

import 'package:finance_tracker/services/home_widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the widget shows this month and today', () {
    final d = homeWidgetData(
        now: DateTime(2026, 11, 7),
        monthSpent: 4523450,
        todaySpent: 49900,
        locked: false);
    expect(d.title, 'Spent in November');
    expect(d.amount, '₹45,235');
    expect(d.detail, 'Today ₹499');
  });

  test('figures are hidden while the app lock is on', () {
    final d = homeWidgetData(
        now: DateTime(2026, 11, 7),
        monthSpent: 4523450,
        todaySpent: 49900,
        locked: true);
    expect(d.amount, isNot(contains('45')));
    expect(d.detail, 'Hidden while app lock is on');
  });

  test('pushing without the widget plugin does not throw', () async {
    await HomeWidgetService.push(
        const HomeWidgetData('Spent in November', '₹1', 'Today ₹0'));
    expect(await HomeWidgetService.launchedFrom(), isNull);
  });
}
