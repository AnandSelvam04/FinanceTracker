import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/date_format.dart';

/// The date line on the add forms: a calendar icon, the date written out
/// ("Fri, 25 Sep 2026") and a Change button that opens the picker.
///
/// The add-expense, add-investment and add-transfer forms each drew their own
/// version — one with an icon, one prefixed "Date:", one showing a raw
/// "2026-09-25" — so the same field looked different on every form.
class DateFieldRow extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final DateTime firstDate;
  final DateTime lastDate;

  const DateFieldRow({
    super.key,
    required this.date,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.event, size: 20, color: mutedTextColor(context)),
          const SizedBox(width: 8),
          Expanded(child: Text(formatDateWithDay(date))),
          TextButton(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: firstDate,
                lastDate: lastDate,
              );
              if (picked != null) onChanged(picked);
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}
