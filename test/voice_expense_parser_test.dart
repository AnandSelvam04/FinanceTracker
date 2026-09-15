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

  test('a leading quantity is not mistaken for the amount', () {
    // "2" is a count of coffees; the spend is 300.
    final r = VoiceExpenseParser.parse('2 coffees for 300',
        knownCategories: categories);
    expect(r.amountMinor, 30000);
    expect(r.type, DbConstants.txExpense);
  });

  test('a number next to a currency word wins over a bare number', () {
    final r = VoiceExpenseParser.parse('300 rupees for food',
        knownCategories: categories);
    expect(r.amountMinor, 30000);
    expect(r.category, 'Food');
  });

  test('"got" no longer flips an expense to income', () {
    final r = VoiceExpenseParser.parse('got coffee for 200',
        knownCategories: categories);
    expect(r.type, DbConstants.txExpense);
    expect(r.amountMinor, 20000);
  });
}
