import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Month stepper shared by the dashboard and the monthly summary screen.
class MonthSelector extends StatefulWidget {
  final void Function(int year, int month) onChanged;
  final int initialYear;
  final int initialMonth;
  const MonthSelector({
    super.key,
    required this.onChanged,
    required this.initialYear,
    required this.initialMonth,
  });

  @override
  State<MonthSelector> createState() => _MonthSelectorState();
}

class _MonthSelectorState extends State<MonthSelector> {
  late int year;
  late int month;

  @override
  void initState() {
    super.initState();
    year = widget.initialYear;
    month = widget.initialMonth;
  }

  void _changeMonth(int delta) {
    setState(() {
      month += delta;
      if (month > 12) {
        month = 1;
        year++;
      } else if (month < 1) {
        month = 12;
        year--;
      }
      widget.onChanged(year, month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: l.previousMonth,
          onPressed: () => _changeMonth(-1),
        ),
        Text(
          '$year-${month.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 16),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: l.nextMonth,
          onPressed: () => _changeMonth(1),
        ),
      ],
    );
  }
}
