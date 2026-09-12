import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/services/voice_expense_parser.dart';
import 'package:finance_tracker/utils/db_constants.dart';

void main() {
  const categories = [
    'Food',
    'Transport',
    'Shopping',
    'Groceries',
    'Salary',
  ];

  test('spent … on … at …', () {
    final r = VoiceExpenseParser.parse(
      'spent 250 on food at Dominos',
      knownCategories: categories,
    );
    expect(r.type, DbConstants.txExpense);
    expect(r.amountMinor, 25000);
    expect(r.category, 'Food');
    expect(r.description, 'Dominos');
  });

  test('income wording flips the type', () {
    final r = VoiceExpenseParser.parse(
      'received 5000 salary',
      knownCategories: categories,
    );
    expect(r.type, DbConstants.txIncome);
    expect(r.amountMinor, 500000);
    expect(r.category, 'Salary');
  });

  test('strips an "add an expense of" lead-in', () {
    final r = VoiceExpenseParser.parse(
      'add an expense of 1200 for groceries',
      knownCategories: categories,
    );
    expect(r.type, DbConstants.txExpense);
    expect(r.amountMinor, 120000);
    expect(r.category, 'Groceries');
  });

  test('bare "<thing> <amount>" fills a description without a category', () {
    final r = VoiceExpenseParser.parse('coffee 120', knownCategories: categories);
    expect(r.amountMinor, 12000);
    expect(r.category, isNull);
    expect(r.description, 'Coffee');
  });

  test('parses grouped amounts', () {
    final r = VoiceExpenseParser.parse('spent 1,250 on shopping',
        knownCategories: categories);
    expect(r.amountMinor, 125000);
    expect(r.category, 'Shopping');
  });

  test('a sentence with no number is empty', () {
    expect(VoiceExpenseParser.parse('hello there').isEmpty, isTrue);
  });
}
