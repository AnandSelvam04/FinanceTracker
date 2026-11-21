import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finance_tracker/models/category_rule.dart';
import 'package:finance_tracker/models/expense.dart';
import 'package:finance_tracker/providers/settings_provider.dart';
import 'package:finance_tracker/services/category_memory.dart';
import 'package:finance_tracker/services/category_rules.dart';
import 'package:finance_tracker/services/csv_import.dart';
import 'package:finance_tracker/services/db_service.dart';
import 'package:finance_tracker/services/sms_import.dart';
import 'package:finance_tracker/services/sms_service.dart';
import 'package:finance_tracker/utils/db_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'category_rules_test.db';

  const expense = DbConstants.txExpense;
  const income = DbConstants.txIncome;

  CategoryRule rule(String pattern, String category,
          {RuleMatch match = RuleMatch.contains,
          String type = expense,
          String? tag,
          bool enabled = true,
          String? id}) =>
      CategoryRule(
        id: id ?? 'id-$pattern-$category',
        match: match,
        pattern: pattern,
        type: type,
        category: category,
        tag: tag,
        enabled: enabled,
      );

  Expense row(String description,
          {String category = 'Other',
          String type = expense,
          int amount = 25000,
          String? note,
          int? id}) =>
      Expense(
        id: id,
        description: description,
        amount: amount,
        date: DateTime(2026, 3, 1),
        category: category,
        paymentMode: 'UPI',
        type: type,
        note: note,
      );

  group('matching', () {
    test('contains ignores case and punctuation', () {
      final r = rule('zomato', 'Food');
      expect(r.matches('ZOMATO ONLINE ORDER', expense), isTrue);
      expect(r.matches('UPI/Zomato-Ltd/123', expense), isTrue);
      expect(r.matches('Swiggy', expense), isFalse);
    });

    test('contains matches at the start of a word, not inside one', () {
      final r = rule('ola', 'Transport');
      expect(r.matches('OLACABS 8812', expense), isTrue);
      expect(r.matches('Ola ride', expense), isTrue);
      // A short needle buried mid-word is too often someone else.
      expect(r.matches('COCA COLA', expense), isFalse);
    });

    test('a longer text is found even glued inside a narration', () {
      expect(rule('zomato', 'Food').matches('POS1234ZOMATO', expense), isTrue);
    });

    test('starts with and is exactly', () {
      final starts = rule('amazon', 'Shopping', match: RuleMatch.startsWith);
      expect(starts.matches('Amazon Pay', expense), isTrue);
      expect(starts.matches('Paid via Amazon', expense), isFalse);
      final exact = rule('rent', 'Bills', match: RuleMatch.exact);
      expect(exact.matches('  Rent. ', expense), isTrue);
      expect(exact.matches('Rent March', expense), isFalse);
    });

    test('a rule only files rows of its own type', () {
      final r = rule('acme', 'Salary', type: income);
      expect(r.matches('ACME PAYROLL', income), isTrue);
      expect(r.matches('ACME PAYROLL', expense), isFalse);
      expect(r.matches('ACME PAYROLL', DbConstants.txTransfer), isFalse);
    });

    test('a switched-off or blank rule matches nothing', () {
      expect(rule('zomato', 'Food', enabled: false).matches('Zomato', expense),
          isFalse);
      expect(rule('  ', 'Food').matches('anything', expense), isFalse);
    });

    test('keeps a UPI handle together', () {
      expect(rule('swiggy@icici', 'Food').matches('UPI swiggy@icici', expense),
          isTrue);
    });

    test('the first matching rule wins', () {
      final rules = [
        rule('amazon prime', 'Entertainment'),
        rule('amazon', 'Shopping'),
      ];
      expect(
          CategoryRules.firstMatch(rules, 'AMAZON PRIME VIDEO', expense)
              ?.category,
          'Entertainment');
      expect(CategoryRules.firstMatch(rules, 'AMAZON', expense)?.category,
          'Shopping');
      expect(CategoryRules.firstMatch(rules, 'FLIPKART', expense), isNull);
    });
  });

  group('tags', () {
    test('are cleaned into something a #tag can hold', () {
      expect(CategoryRule.cleanTag('#Eating Out'), 'eating-out');
      expect(CategoryRule.cleanTag('  ##office! '), 'office');
      expect(CategoryRule.cleanTag('#'), isNull);
      expect(CategoryRule.cleanTag(null), isNull);
    });

    test('are added to a note once', () {
      expect(CategoryRules.noteWithTag(null, 'eatingout'), '#eatingout');
      expect(CategoryRules.noteWithTag('team lunch', 'eatingout'),
          'team lunch #eatingout');
      expect(CategoryRules.noteWithTag('lunch #EatingOut', 'eatingout'),
          'lunch #EatingOut');
      expect(CategoryRules.noteWithTag('lunch', null), 'lunch');
    });
  });

  group('changes to past transactions', () {
    test('sets the category and adds the tag', () {
      final r = rule('zomato', 'Food', tag: 'eatingout');
      final c = CategoryRules.changeFor(row('Zomato', id: 1), r)!;
      expect(c.category, 'Food');
      expect(c.note, '#eatingout');
      expect(c.reverted.category, 'Other');
      expect(c.reverted.note, isNull);
    });

    test('leaves a row already filed that way alone', () {
      final r = rule('zomato', 'Food', tag: 'eatingout');
      expect(
          CategoryRules.changeFor(
              row('Zomato', category: 'food', note: '#eatingout'), r),
          isNull);
    });

    test('never touches a transfer', () {
      final r = rule('hdfc', 'Bills');
      expect(
          CategoryRules.changes(
              [r], [row('HDFC', type: DbConstants.txTransfer, id: 1)]),
          isEmpty);
    });

    test('a refund is an expense for rules', () {
      final r = rule('amazon', 'Shopping');
      expect(
          CategoryRules.changes(
                  [r], [row('Amazon refund', amount: -5000, id: 1)])
              .single
              .category,
          'Shopping');
    });

    test('one rule run on its own leaves rows an earlier rule claims', () {
      final prime = rule('amazon prime', 'Entertainment');
      final amazon = rule('amazon', 'Shopping');
      final rows = [row('Amazon Prime', id: 1), row('Amazon', id: 2)];
      final only = CategoryRules.changes([prime, amazon], rows, only: amazon);
      expect(only.map((c) => c.row.id), [2]);
      final all = CategoryRules.changes([prime, amazon], rows);
      expect(all.map((c) => c.category), ['Entertainment', 'Shopping']);
    });

    test('a pattern made from a description drops the reference number', () {
      expect(CategoryRules.patternFrom('SWIGGY 88213'), 'swiggy');
      expect(CategoryRules.patternFrom('Zomato Ltd.'), 'zomato ltd');
    });
  });

  group('store', () {
    final store = CategoryRuleStore.instance;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await store.load();
    });

    test('keeps rules, in order, across a restart', () async {
      await store.add(rule('zomato', 'Food', tag: 'eatingout', id: 'a'));
      await store.add(rule('uber', 'Transport', id: 'b'));
      await store.load();
      expect(store.rules.map((r) => r.id), ['a', 'b']);
      expect(store.rules.first.tag, 'eatingout');
      expect(store.firstMatch('UBER TRIP', expense)?.category, 'Transport');
    });

    test('reorders, edits, removes and restores', () async {
      await store.add(rule('a', 'A', id: '1'));
      await store.add(rule('b', 'B', id: '2'));
      await store.add(rule('c', 'C', id: '3'));
      await store.reorder(2, 0);
      expect(store.rules.map((r) => r.id), ['3', '1', '2']);
      await store.update(store.byId('1')!.copyWith(enabled: false));
      expect(store.byId('1')!.enabled, isFalse);
      final removed = store.byId('1')!;
      final at = await store.remove('1');
      expect(store.rules.map((r) => r.id), ['3', '2']);
      await store.add(removed, index: at);
      expect(store.rules.map((r) => r.id), ['3', '1', '2']);
    });

    test('follows a category rename or merge', () async {
      await store.add(rule('zomato', 'Food', id: '1'));
      await store.add(rule('acme', 'Food', type: income, id: '2'));
      final n = await store.renameCategory(expense, 'food', 'Eating out');
      expect(n, 1);
      expect(store.byId('1')!.category, 'Eating out');
      // An income category of the same name is another category.
      expect(store.byId('2')!.category, 'Food');
    });

    test('a damaged entry loses only itself', () async {
      SharedPreferences.setMockInitialValues({
        CategoryRuleStore.prefsKey:
            '[{"id":"ok","p":"uber","c":"Transport"},{"p":3},"junk"]',
      });
      await store.load();
      expect(store.rules.single.id, 'ok');

      SharedPreferences.setMockInitialValues(
          {CategoryRuleStore.prefsKey: 'not json'});
      await store.load();
      expect(store.rules, isEmpty);
    });

    test('travels in backups with the other settings', () async {
      await store.add(rule('zomato', 'Food', id: '1'));
      final exported = await SettingsProvider.exportForBackup();
      expect(exported, contains(CategoryRuleStore.prefsKey));

      SharedPreferences.setMockInitialValues({});
      await store.load();
      expect(store.rules, isEmpty);
      await SettingsProvider.importFromBackup(exported);
      await store.load();
      expect(store.rules.single.category, 'Food');
    });
  });

  group('imports', () {
    final received = DateTime(2026, 3, 2, 10);

    ParsedSms parse(String body) =>
        SmsImport.parse(sender: 'VM-HDFCBK', body: body, receivedAt: received)!;

    test('an SMS is filed by a rule over the remembered category', () {
      final parsed =
          parse('Rs.450.00 spent on Card XX1234 at ZOMATO on 02-Mar-26');
      final memory = CategoryMemory.fromRows([
        {
          DbConstants.colDescription: parsed.description,
          DbConstants.colCategory: 'Shopping',
          'n': 3,
          'lastDate': '2026-01-01T00:00:00.000',
        }
      ]);
      final draft = SmsDraft.from(parsed, const [],
          memory: memory, rules: [rule('zomato', 'Food', tag: 'eatingout')]);
      expect(draft.category, 'Food');
      expect(draft.filedByRule, isTrue);
      expect(draft.toExpense().note, '#eatingout');

      // Changed by hand on the review screen: the rule's tag goes with it.
      draft.category = 'Shopping';
      expect(draft.filedByRule, isFalse);
      expect(draft.toExpense().note, isNull);
    });

    test('an SMS no rule matches keeps the usual category', () {
      final parsed =
          parse('Rs.450.00 spent on Card XX1234 at ZOMATO on 02-Mar-26');
      final draft =
          SmsDraft.from(parsed, const [], rules: [rule('uber', 'Transport')]);
      expect(draft.rule, isNull);
      expect(draft.category, 'Food'); // the merchant-name guess
      expect(draft.toExpense().note, isNull);
    });

    test('a CSV row with no category is filed by a rule', () {
      final result = parseCsvExpenses(
        [
          ['Date', 'Narration', 'Amount', 'Category'],
          ['01/03/2026', 'UPI-ZOMATO-ORDER', '-450', ''],
          ['02/03/2026', 'UPI-ZOMATO-ORDER', '-300', 'Gifts'],
          ['03/03/2026', 'UPI-OTHER', '-100', ''],
        ],
        hasHeader: true,
        mapping: const CsvColumnMapping(
            dateCol: 0, descriptionCol: 1, amountCol: 2, categoryCol: 3),
        rules: [rule('zomato', 'Food', tag: 'eatingout')],
      );
      final rows = result.expenses;
      expect(rows[0].category, 'Food');
      expect(rows[0].note, '#eatingout');
      // The file's own category is what the user exported; it stays.
      expect(rows[1].category, 'Gifts');
      expect(rows[1].note, isNull);
      expect(rows[2].category, 'Other');
    });
  });

  group('database', () {
    setUp(() async => DBService().clearAll());

    test('sets and restores categories and notes together', () async {
      final a = await DBService().insertExpense(row('Zomato'));
      final b = await DBService().insertExpense(row('Zomato', note: 'lunch'));
      final t = await DBService()
          .insertExpense(row('Zomato', type: DbConstants.txTransfer));
      final n = await DBService().setCategoriesAndNotes({
        a: (category: 'Food', note: '#eatingout'),
        b: (category: 'Food', note: 'lunch #eatingout'),
        t: (category: 'Food', note: '#eatingout'),
      });
      expect(n, 2);
      final byId = {for (final e in await DBService().getExpenses()) e.id: e};
      expect(byId[a]!.category, 'Food');
      expect(byId[a]!.note, '#eatingout');
      expect(byId[b]!.note, 'lunch #eatingout');
      expect(byId[t]!.category, isNot('Food'));

      await DBService().setCategoriesAndNotes({
        a: (category: 'Other', note: null),
      });
      final undone =
          (await DBService().getExpenses()).firstWhere((e) => e.id == a);
      expect(undone.category, 'Other');
      expect(undone.note, isNull);
    });
  });
}
