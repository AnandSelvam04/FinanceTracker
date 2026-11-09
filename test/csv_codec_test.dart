import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the behaviour the CSV import and exports rely on, so a change in the
/// csv package (8.0 was a rewrite) shows up here rather than in a statement.
void main() {
  final reader = Csv(autoDetect: false);

  test('reads quoted commas, quotes and line breaks inside cells', () {
    final rows = reader.decode('Date,Narration,Amount\r\n'
        '01/02/2026,"UPI/SWIGGY, Bangalore",450.00\r\n'
        '02/02/2026,"He said ""hi""\nthen paid",12\r\n');
    expect(rows, [
      ['Date', 'Narration', 'Amount'],
      ['01/02/2026', 'UPI/SWIGGY, Bangalore', '450.00'],
      ['02/02/2026', 'He said "hi"\nthen paid', '12'],
    ]);
  });

  test('keeps every cell as text, leading zeros and all', () {
    final row = reader.decode('0012345,1e3,true,-5.50\r\n').single;
    expect(row, ['0012345', '1e3', 'true', '-5.50']);
    expect(row.every((c) => c is String), isTrue);
  });

  test('reads files that end lines with \\n only', () {
    expect(reader.decode('a,b\n1,2\n'), [
      ['a', 'b'],
      ['1', '2'],
    ]);
  });

  test('does not guess another delimiter for a comma file', () {
    expect(reader.decode('Desc;Note,Amount\r\nTea;hot,20\r\n'), [
      ['Desc;Note', 'Amount'],
      ['Tea;hot', '20'],
    ]);
  });

  test('an export reads back unchanged', () {
    final rows = [
      ['Date', 'Description', 'Amount'],
      ['2026-02-01', 'Rent, Feb', '25000.00'],
      ['2026-02-02', 'Quote "x"', '-10.00'],
    ];
    final text = csv.encode(rows);
    expect(text, contains('"Rent, Feb"'));
    expect(reader.decode(text), rows);
  });
}
