import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/services/category_memory.dart';
import 'package:finance_tracker/utils/db_constants.dart';

void main() {
  Map<String, Object?> row(String description, String category, {int n = 1}) => {
        DbConstants.colDescription: description,
        DbConstants.colCategory: category,
        'n': n,
        'lastDate': '2025-08-01T00:00:00.000',
      };

  group('merchantKey', () {
    test('ignores case and surrounding whitespace', () {
      expect(CategoryMemory.merchantKey('  Swiggy '),
          CategoryMemory.merchantKey('SWIGGY'));
    });

    test('ignores trailing punctuation', () {
      expect(CategoryMemory.merchantKey('SWIGGY.'),
          CategoryMemory.merchantKey('SWIGGY'));
    });

    test('collapses repeated spaces', () {
      expect(CategoryMemory.merchantKey('AMAZON   PAY'),
          CategoryMemory.merchantKey('AMAZON PAY'));
    });

    test('drops a trailing reference number', () {
      // Banks append a txn reference that differs every time; without this
      // every purchase would look like a new merchant and never be recalled.
      expect(CategoryMemory.merchantKey('SWIGGY 88213'),
          CategoryMemory.merchantKey('SWIGGY'));
    });

    test('keeps digits that are part of the name', () {
      expect(CategoryMemory.merchantKey('7ELEVEN'), '7ELEVEN');
    });

    test('keeps a UPI handle intact', () {
      expect(CategoryMemory.merchantKey('merchant@ybl'), 'MERCHANT@YBL');
    });

    test('distinguishes genuinely different merchants', () {
      expect(CategoryMemory.merchantKey('SWIGGY'),
          isNot(CategoryMemory.merchantKey('ZOMATO')));
    });

    test('is empty for a description with nothing usable', () {
      expect(CategoryMemory.merchantKey('---'), isEmpty);
    });
  });

  group('recall', () {
    test('returns the category a merchant was filed under', () {
      final memory = CategoryMemory.fromRows([row('SWIGGY', 'Food')]);
      expect(memory.categoryFor('SWIGGY'), 'Food');
    });

    test('recalls across formatting differences', () {
      final memory = CategoryMemory.fromRows([row('SWIGGY', 'Food')]);
      expect(memory.categoryFor('Swiggy 4471'), 'Food');
    });

    test('is null for an unfamiliar merchant', () {
      final memory = CategoryMemory.fromRows([row('SWIGGY', 'Food')]);
      expect(memory.categoryFor('ZOMATO'), isNull);
    });

    test('the first row for a merchant wins', () {
      // The query orders by count then recency, so the leading row is the
      // category the user picks most often for that merchant.
      final memory = CategoryMemory.fromRows([
        row('SWIGGY', 'Food', n: 9),
        row('SWIGGY', 'Entertainment', n: 1),
      ]);
      expect(memory.categoryFor('SWIGGY'), 'Food');
    });

    test('holds several merchants at once', () {
      final memory = CategoryMemory.fromRows([
        row('SWIGGY', 'Food'),
        row('AMAZON', 'Shopping'),
        row('TNEB', 'Bills'),
      ]);
      expect(memory.categoryFor('AMAZON'), 'Shopping');
      expect(memory.categoryFor('TNEB'), 'Bills');
    });

    test('skips rows with an empty or non-string category', () {
      final memory = CategoryMemory.fromRows([
        row('SWIGGY', '   '),
        {DbConstants.colDescription: 'AMAZON', DbConstants.colCategory: null},
        row('ZOMATO', 'Food'),
      ]);
      expect(memory.categoryFor('SWIGGY'), isNull);
      expect(memory.categoryFor('AMAZON'), isNull);
      expect(memory.categoryFor('ZOMATO'), 'Food');
    });

    test('an empty memory recalls nothing', () {
      expect(const CategoryMemory.empty().categoryFor('SWIGGY'), isNull);
      expect(const CategoryMemory.empty().isEmpty, isTrue);
      expect(CategoryMemory.fromRows(const []).isEmpty, isTrue);
    });
  });
}
