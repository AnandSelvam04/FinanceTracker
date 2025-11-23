class Investment {
  final int? id;
  final String name;
  final double amount;
  final DateTime date;
  final String type;

  Investment({
    this.id,
    required this.name,
    required this.amount,
    required this.date,
    required this.type,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'amount': amount,
        'date': date.toIso8601String(),
        'type': type,
      };

  factory Investment.fromMap(Map<String, dynamic> map) => Investment(
        id: map['id'],
        name: map['name'],
        amount: map['amount'],
        date: DateTime.parse(map['date']),
        type: map['type'],
      );
}
