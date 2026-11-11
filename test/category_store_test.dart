import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_tracker/providers/settings_provider.dart';
import 'package:finance_tracker/utils/category_colors.dart';
import 'package:finance_tracker/utils/category_icons.dart';
import 'package:finance_tracker/utils/category_store.dart';
import 'package:finance_tracker/utils/db_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const expense = DbConstants.txExpense;
  const income = DbConstants.txIncome;
  final store = CategoryStore.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await store.load();
  });

  test('offers the built-in categories when nothing is stored', () {
    expect(store.offered(expense), defaultExpenseCategories);
    expect(store.offered(income), defaultIncomeCategories);
    expect(categoryIcon('Food'), Icons.restaurant);
  });

  test('a new category is offered first and keeps its icon and colour',
      () async {
    await store.put(expense, 'Rent', icon: 'home', color: 0xFF00897B);
    expect(store.offered(expense).first, 'Rent');
    expect(store.offered(income), isNot(contains('Rent')));
    expect(categoryIcon('rent '), Icons.home);
    expect(CategoryColors.forCategory('Rent'), const Color(0xFF00897B));

    // Survives a restart.
    await store.load();
    expect(store.offered(expense).first, 'Rent');
    expect(categoryIcon('Rent'), Icons.home);
  });

  test('a built-in category can be restyled without being duplicated',
      () async {
    await store.put(expense, 'food', icon: 'cafe');
    expect(categoryIcon('Food'), Icons.local_cafe);
    expect(
        store.offered(expense).where((c) => c.toLowerCase() == 'food').length,
        1);
  });

  test('removing forgets a custom category and hides a built-in one',
      () async {
    await store.put(expense, 'Rent');
    await store.remove(expense, 'Rent');
    await store.remove(expense, 'Education');
    expect(store.offered(expense), isNot(contains('Rent')));
    expect(store.offered(expense), isNot(contains('Education')));
    // Hidden for expenses only.
    expect(store.offered(income), defaultIncomeCategories);
    // Adding it again brings it back.
    await store.put(expense, 'Education');
    expect(store.offered(expense), contains('Education'));
  });

  test('a rename carries the look over; a merge drops it', () async {
    await store.put(expense, 'Rent', icon: 'home', color: 0xFF00897B);
    await store.rename(expense, 'Rent', 'Housing', merged: false);
    expect(store.offered(expense), contains('Housing'));
    expect(store.offered(expense), isNot(contains('Rent')));
    expect(categoryIcon('Housing'), Icons.home);

    await store.rename(expense, 'Housing', 'Bills', merged: true);
    expect(store.offered(expense), isNot(contains('Housing')));
    expect(categoryIcon('Bills'), Icons.receipt_long);
  });

  test('renaming a built-in category stops offering the old name', () async {
    await store.rename(expense, 'Food', 'Food & Dining', merged: false);
    expect(store.offered(expense), contains('Food & Dining'));
    expect(store.offered(expense), isNot(contains('Food')));
  });

  test('ensure adds an unknown name once and leaves built-ins alone',
      () async {
    await store.ensure(expense, 'Pets');
    await store.ensure(expense, 'pets');
    await store.ensure(expense, 'Food');
    expect(store.offered(expense).where((c) => c == 'Pets').length, 1);
    expect(store.entry(expense, 'Food'), isNull);
  });

  test('damaged or unknown stored values are ignored', () async {
    SharedPreferences.setMockInitialValues({CategoryStore.prefsKey: '{oops'});
    await store.load();
    expect(store.offered(expense), defaultExpenseCategories);

    SharedPreferences.setMockInitialValues({
      CategoryStore.prefsKey:
          '{"expense":[{"n":"Rent","i":"no-such-icon","c":"red"},{"x":1}]}'
    });
    await store.load();
    expect(store.offered(expense).first, 'Rent');
    expect(store.entry(expense, 'Rent')!.icon, isNull);
    expect(store.entry(expense, 'Rent')!.color, isNull);
  });

  test('categories travel in a backup with the other settings', () async {
    await store.put(expense, 'Rent', icon: 'home');
    final exported = await SettingsProvider.exportForBackup();
    expect(exported[CategoryStore.prefsKey], isA<String>());

    SharedPreferences.setMockInitialValues({});
    await store.load();
    expect(store.offered(expense), isNot(contains('Rent')));

    await SettingsProvider.importFromBackup(exported);
    await SettingsProvider().load();
    expect(store.offered(expense), contains('Rent'));
    expect(categoryIcon('Rent'), Icons.home);
  });
}
