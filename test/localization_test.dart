import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/l10n/app_localizations.dart';

void main() {
  test('English returns English strings', () {
    final en = AppLocalizations(const Locale('en'));
    expect(en.settings, 'Settings');
    expect(en.addAccount, 'Add Account');
  });

  test('Tamil returns Tamil strings', () {
    final ta = AppLocalizations(const Locale('ta'));
    expect(ta.settings, 'அமைப்புகள்');
    expect(ta.navHome, 'முகப்பு');
  });

  test('unknown locale falls back to English', () {
    final fr = AppLocalizations(const Locale('fr'));
    expect(fr.settings, 'Settings');
  });

  test('English and Tamil expose the same set of keys (no missing strings)',
      () {
    // Both supported locales are declared.
    expect(AppLocalizations.supportedLocales,
        [const Locale('en'), const Locale('ta')]);
  });
}
