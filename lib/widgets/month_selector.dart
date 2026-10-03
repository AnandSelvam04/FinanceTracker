import 'package:flutter/material.dart';

import '../utils/date_format.dart';

/// Month stepper shared by the dashboard and the monthly summary screen.
class MonthSelector extends StatefulWidget {
  final void Function(int year, int month) onChanged;
  final int initialYear;
  final int initialMonth;

  /// Step and show whole years instead of months — for the dashboard's Year
  /// view, where a "September 2026" label misread as a monthly figure.
  final bool yearOnly;
  const MonthSelector({
    super.key,
    required this.onChanged,
    required this.initialYear,
    required this.initialMonth,
    this.yearOnly = false,
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
      final total = year * 12 + (month - 1) + delta;
      year = total ~/ 12;
      month = total % 12 + 1;
      widget.onChanged(year, month);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: widget.yearOnly ? 'Previous year' : 'Previous month',
          onPressed: () => _changeMonth(widget.yearOnly ? -12 : -1),
        ),
        // A fixed width keeps the arrows from shifting as month names change
        // length ("May" vs "September").
        SizedBox(
          width: 150,
          child: Text(
            widget.yearOnly ? '$year' : formatMonthYear(year, month),
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: widget.yearOnly ? 'Next year' : 'Next month',
          onPressed: () => _changeMonth(widget.yearOnly ? 12 : 1),
        ),
      ],
    );
  }
}
