import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/services/sms_import.dart';
import 'package:finance_tracker/utils/db_constants.dart';

/// The not-a-transaction filter no longer drops real alerts that happen to
/// contain a promo word or a reversal; a same-day body date keeps the arrival
/// time; and more of the date shapes banks use are read.
void main() {
  final received = DateTime(2025, 8, 1, 14, 30);

  ParsedSms? parse(String body) =>
      SmsImport.parse(sender: 'VM-HDFCBK', body: body, receivedAt: received);

  group('promo words', () {
    test('a merchant named with a promo word is still a purchase', () {
      final win = parse('Rs.320 spent on Credit Card XX5678 at WIN MART')!;
      expect(win.type, DbConstants.txExpense);
      expect(win.description, 'WIN MART');

      final sale = parse('Rs.1,499 debited from A/c XX4821 to MEGA SALE')!;
      expect(sale.amount, 149900);
      expect(sale.description, 'MEGA SALE');
    });

    test('a real alert with an offer footer is kept', () {
      final r = parse('Rs.499 debited from A/c XX4821 to SWIGGY. '
          'Get 10% off on your next order - offer from HDFC Bank')!;
      expect(r.description, 'SWIGGY');
    });

    test('cashback that was credited is recorded', () {
      final r = parse('Congratulations! Rs.50 cashback credited to your '
          'A/c XX4821')!;
      expect(r.type, DbConstants.txIncome);
      expect(r.isCashback, isTrue);
    });

    for (final advert in [
      'Flat Rs.200 off on orders above Rs.999! Sale ends tonight at MYNTRA.',
      'Congratulations! You have won a voucher worth Rs.5,000 from AMAZON.',
      'Exclusive offer: get Rs.100 discount on your first UPI payment.',
      'Pre-approved loan of Rs.5,00,000 credited in 10 mins. Tap to accept.',
    ]) {
      test('an advert is still dropped: "${advert.substring(0, 28)}..."', () {
        expect(parse(advert), isNull);
      });
    }
  });

  group('reversals', () {
    test('money reversed to the account is a refund', () {
      final r = parse('Rs.500 reversed to your A/c XX4821 for txn on '
          '30-Jul-25 at AMAZON')!;
      expect(r.isRefund, isTrue);
      expect(r.recordedType, DbConstants.txExpense);
      expect(r.signedAmount, -50000);
      expect(r.last4, '4821');
    });

    test('a promised reversal is not recorded yet', () {
      expect(
          parse('Rs.500 for your failed txn will be reversed to A/c XX4821 '
              'in 5 days'),
          isNull);
      expect(parse('Rs.500 will be refunded to your A/c XX4821'), isNull);
    });
  });

  group('time of day', () {
    test('a body date on the day it arrived keeps the arrival time', () {
      final r = parse('Rs.499 debited from A/c XX4821 on 01-Aug-25 to SWIGGY')!;
      expect(r.date, received);
    });

    test('an earlier body date is still used', () {
      final r = parse('Rs.499 debited from A/c XX4821 on 30-Jul-25 to SWIGGY')!;
      expect(r.date, DateTime(2025, 7, 30));
    });
  });

  group('date shapes', () {
    DateTime dateOf(String when) =>
        parse('Rs.499 debited from A/c XX4821 on $when to SWIGGY')!.date;

    test('day month-name year, with or without spaces', () {
      expect(dateOf('30 Jul 2025'), DateTime(2025, 7, 30));
      expect(dateOf('30 July 2025'), DateTime(2025, 7, 30));
      expect(dateOf('30Jul25'), DateTime(2025, 7, 30));
      expect(dateOf('28 Sept, 2025'), received); // later than arrival
      expect(dateOf('29 Jul, 2025'), DateTime(2025, 7, 29));
    });

    test('month-name first', () {
      expect(dateOf('Jul 30, 2025'), DateTime(2025, 7, 30));
      expect(dateOf('July 30th 2025'), DateTime(2025, 7, 30));
    });

    test('ISO', () {
      expect(dateOf('2025-07-30'), DateTime(2025, 7, 30));
    });

    test('a word that only starts like a month is not one', () {
      expect(dateOf('30 Market 2025'), received);
    });

    test('the first date in the message wins', () {
      final r = parse('Rs.499 debited from A/c XX4821 on 29 Jul 2025 to '
          'SWIGGY. Bill date 2025-07-31')!;
      expect(r.date, DateTime(2025, 7, 29));
    });
  });
}
