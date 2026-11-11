import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finance_tracker/providers/settings_provider.dart';
import 'package:finance_tracker/utils/dashboard_layout.dart';

void main() {
  group('normaliseOrder', () {
    test('nothing saved gives the default order', () {
      expect(
          DashboardLayout.normaliseOrder(null), DashboardLayout.defaultOrder);
      expect(DashboardLayout.normaliseOrder(''), DashboardLayout.defaultOrder);
    });

    test('keeps a saved order', () {
      final saved = DashboardLayout.defaultOrder.reversed.toList();
      expect(DashboardLayout.normaliseOrder(saved.join(',')), saved);
    });

    test('drops unknown ids and repeats', () {
      final order =
          DashboardLayout.normaliseOrder('trends,bogus,trends,netWorth');
      expect(order.toSet().length, order.length);
      expect(order.toSet(), DashboardLayout.defaultOrder.toSet());
      expect(order.indexOf('trends'), lessThan(order.indexOf('netWorth')));
    });

    test('a section the saved order never knew goes after its neighbour', () {
      // Saved before "insights" existed: it belongs right after "figures".
      final order = DashboardLayout.normaliseOrder(
          'recent,figures,netWorth,quickAdd,shortcuts,categories,merchants,trends');
      expect(order.indexOf('insights'), order.indexOf('figures') + 1);
      expect(order.first, 'recent');
    });
  });

  test('the period figures cannot be hidden', () {
    expect(DashboardLayout.normaliseHidden('figures,trends,bogus'), {'trends'});
  });

  group('normaliseShortcuts', () {
    test('never chosen gives the defaults; chosen empty stays empty', () {
      expect(DashboardLayout.normaliseShortcuts(null),
          DashboardLayout.defaultShortcuts);
      expect(DashboardLayout.normaliseShortcuts(''), isEmpty);
    });

    test('keeps at most four known shortcuts, in the order picked', () {
      expect(
          DashboardLayout.normaliseShortcuts(
              'goals,bogus,cards,goals,reports,loans,accounts'),
          ['goals', 'cards', 'reports', 'loans']);
    });
  });

  test('every section and shortcut has a label', () {
    for (final id in DashboardLayout.defaultOrder) {
      expect(DashboardLayout.sectionLabels[id], isNotNull, reason: id);
    }
    for (final id in DashboardLayout.allShortcuts) {
      expect(DashboardLayout.shortcutLabels[id], isNotNull, reason: id);
    }
  });

  group('SettingsProvider', () {
    test('saves the layout and reads it back', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.load();
      expect(settings.dashboardSections, DashboardLayout.defaultOrder);

      final order = DashboardLayout.defaultOrder.reversed.toList();
      await settings
          .setDashboardLayout(order: order, hidden: {'trends', 'figures'});
      await settings.setHomeShortcuts(['goals', 'reports']);

      final reloaded = SettingsProvider();
      await reloaded.load();
      expect(reloaded.dashboardOrder, order);
      // "figures" is refused: it carries the month stepper.
      expect(reloaded.dashboardHidden, {'trends'});
      expect(reloaded.dashboardSections, [...order]..remove('trends'));
      expect(reloaded.homeShortcuts, ['goals', 'reports']);
    });

    test('the layout and the theme choices travel in a backup', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.load();
      await settings.setTrueBlack(true);
      await settings.setHomeShortcuts(['cards']);
      final backup = await SettingsProvider.exportForBackup();

      SharedPreferences.setMockInitialValues({});
      await SettingsProvider.importFromBackup(backup);
      final restored = SettingsProvider();
      await restored.load();
      expect(restored.trueBlack, isTrue);
      expect(restored.homeShortcuts, ['cards']);
    });

    test('picking an accent by hand stops following the wallpaper', () async {
      SharedPreferences.setMockInitialValues(
          {'useWallpaperAccent': true, 'wallpaperAccentValue': 0xFF006C4C});
      final settings = SettingsProvider();
      await settings.load();
      expect(settings.useWallpaperAccent, isTrue);
      expect(settings.themeSeed.toARGB32(), 0xFF006C4C);

      await settings.setSeedColor(SettingsProvider.seedOptions[2]);
      expect(settings.useWallpaperAccent, isFalse);
      expect(settings.themeSeed, SettingsProvider.seedOptions[2]);
    });

    test('with no wallpaper colour on offer the chosen accent is used',
        () async {
      SharedPreferences.setMockInitialValues({'useWallpaperAccent': true});
      final settings = SettingsProvider();
      await settings.load();
      expect(settings.useWallpaperAccent, isFalse);
      expect(settings.themeSeed, settings.seedColor);
    });
  });
}
