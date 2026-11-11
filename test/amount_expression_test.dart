import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/utils/amount_expression.dart';
import 'package:finance_tracker/utils/currency_format.dart';

void main() {
  group('evaluateAmountExpression', () {
    test('adds, subtracts, multiplies and divides', () {
      expect(evaluateAmountExpression('250+80'), 330);
      expect(evaluateAmountExpression('1200/3'), 400);
      expect(evaluateAmountExpression('500-120.50'), 379.5);
      expect(evaluateAmountExpression('12*3'), 36);
    });

    test('multiplies and divides before adding', () {
      expect(evaluateAmountExpression('100+50*2'), 200);
      expect(evaluateAmountExpression('(100+50)*2'), 300);
      expect(evaluateAmountExpression('900/3/3'), 100);
    });

    test('accepts the keys the bar inserts, and grouped figures', () {
      expect(evaluateAmountExpression('1,250 × 2'), 2500);
      expect(evaluateAmountExpression('900 ÷ 3'), 300);
      expect(evaluateAmountExpression('500 − 50'), 450);
      expect(evaluateAmountExpression('3x40'), 120);
    });

    test('rejects what is not a finished sum', () {
      expect(evaluateAmountExpression('250+'), isNull);
      expect(evaluateAmountExpression('*5'), isNull);
      expect(evaluateAmountExpression('(2+3'), isNull);
      expect(evaluateAmountExpression('2+3)'), isNull);
      expect(evaluateAmountExpression('1.2.3+1'), isNull);
      expect(evaluateAmountExpression('abc'), isNull);
      expect(evaluateAmountExpression(''), isNull);
    });

    test('dividing by zero is not an amount', () {
      expect(evaluateAmountExpression('100/0'), isNull);
      expect(evaluateAmountExpression('100/(5-5)'), isNull);
    });

    test('a long run of brackets or minus signs is refused, not a crash', () {
      expect(evaluateAmountExpression('${'(' * 150}1${')' * 49}'), isNull);
      expect(evaluateAmountExpression('${'-' * 150}1'), isNull);
    });
  });

  group('isAmountExpression', () {
    test('a plain figure, even a negative one, is not a sum', () {
      expect(isAmountExpression('250'), isFalse);
      expect(isAmountExpression('-250.50'), isFalse);
      expect(isAmountExpression('1,250'), isFalse);
    });

    test('an operator after a figure makes it one', () {
      expect(isAmountExpression('250+'), isTrue);
      expect(isAmountExpression('250 × 2'), isTrue);
      expect(isAmountExpression('(2+3)*4'), isTrue);
    });
  });

  group('amount fields', () {
    test('parse a sum to minor units', () {
      expect(parseMinor('250+80'), 33000);
      expect(parseMinor('1000/3'), 33333);
      expect(parseMinor('99.99*2'), 19998);
    });

    test('still parse plain figures as before', () {
      expect(parseMinor('1,250.50'), 125050);
      expect(parseMinor('-75'), -7500);
      expect(parseMinor('1e300'), isNull);
      expect(parseMinor('abc'), isNull);
    });

    test('validate a sum by its result', () {
      expect(validateAmountField('250+80'), isNull);
      expect(validateAmountField('250+'), 'Enter a valid amount');
      expect(
          validateAmountField('100-100'), 'Enter an amount greater than zero');
      expect(validateAmountField('100-250'), 'Enter a positive amount');
      expect(validateAmountField('100-100', allowZero: true), isNull);
    });
  });
}
