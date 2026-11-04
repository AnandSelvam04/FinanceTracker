import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../utils/app_colors.dart';
import '../utils/currency_format.dart';
import '../utils/daily_spend.dart';
import '../utils/date_format.dart';
import '../utils/insets.dart';
import '../widgets/category_avatar.dart';
import '../widgets/month_selector.dart';
import '../widgets/section_header.dart';

/// A month of spending laid out as a calendar, each day shaded by how much
/// went out. Totals hide which days were heavy and which were quiet; this
/// shows the rhythm (weekend spikes, the rent day, the no-spend streaks) at a
/// glance. Tap a day for its transactions.
class SpendingCalendarScreen extends StatefulWidget {
  const SpendingCalendarScreen({super.key});

  @override
  State<SpendingCalendarScreen> createState() => _SpendingCalendarScreenState();
}

class _SpendingCalendarScreenState extends State<SpendingCalendarScreen> {
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;

  /// Day of month selected, or null for none.
  int? _day = DateTime.now().day;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<ExpenseProvider>().ensureYearLoaded(_year));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ExpenseProvider>(
      builder: (context, provider, _) {
        final rows = provider.expensesForMonth(_year, _month);
        final perDay = dailySpend(rows, provider.baseAmountOf);
        final max = perDay.values.fold<int>(0, (m, v) => v > m ? v : m);
        final total = perDay.values.fold<int>(0, (s, v) => s + v);
        final today = DateUtils.dateOnly(DateTime.now());
        final daysInMonth = DateUtils.getDaysInMonth(_year, _month);
        // Only days that have happened count towards no-spend days and the
        // daily average, so the current month isn't flattered by the future.
        final elapsed = (_year == today.year && _month == today.month)
            ? today.day
            : (DateTime(_year, _month).isAfter(today) ? 0 : daysInMonth);
        final noSpendDays = [
          for (var d = 1; d <= elapsed; d++)
            if ((perDay[d] ?? 0) <= 0) d
        ].length;
        final day = (_day != null && _day! <= daysInMonth) ? _day : null;
        final dayRows = day == null
            ? const <Expense>[]
            : (rows.where((e) => e.date.day == day && !e.isTransfer).toList()
              ..sort((a, b) => b.date.compareTo(a.date)));

        return Scaffold(
          appBar: AppBar(title: const Text('Spending Calendar')),
          body: ListView(
            padding: scrollPadding(context),
            children: [
              MonthSelector(
                initialYear: _year,
                initialMonth: _month,
                onChanged: (y, m) {
                  setState(() {
                    _year = y;
                    _month = m;
                    _day = null;
                  });
                  provider.ensureYearLoaded(y);
                },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatChip(label: 'Spent', value: formatMoneyRounded(total)),
                  _StatChip(
                      label: 'Per day',
                      value: formatMoneyRounded(
                          elapsed == 0 ? 0 : (total / elapsed).round())),
                  _StatChip(label: 'No-spend days', value: '$noSpendDays'),
                  if (max > 0)
                    _StatChip(
                        label: 'Biggest day', value: formatMoneyRounded(max)),
                ],
              ),
              const SizedBox(height: 12),
              _MonthGrid(
                year: _year,
                month: _month,
                perDay: perDay,
                max: max,
                today: today,
                selected: day,
                onSelect: (d) => setState(() => _day = d == _day ? null : d),
              ),
              const SizedBox(height: 8),
              const _Legend(),
              if (day != null) ...[
                const SizedBox(height: 8),
                SectionHeader(formatDateWithDay(DateTime(_year, _month, day))),
                if (dayRows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('Nothing recorded on this day.',
                        style: TextStyle(color: mutedTextColor(context))),
                  )
                else
                  Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final e in dayRows)
                          ListTile(
                            leading: CategoryAvatar(category: e.category),
                            title: Text(
                                e.description.isEmpty
                                    ? e.category
                                    : e.description,
                                overflow: TextOverflow.ellipsis),
                            subtitle: Text(e.category,
                                overflow: TextOverflow.ellipsis),
                            trailing: Text(
                              e.isIncome
                                  ? '+${formatMoney(provider.baseAmountOf(e))}'
                                  : formatMoney(provider.baseAmountOf(e)),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: e.isIncome ? incomeColor(context) : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: mutedTextColor(context))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// Shade for heat level 1–4 (0 is no fill).
Color _heat(BuildContext context, int level) =>
    expenseColor(context).withValues(alpha: 0.14 + 0.18 * (level - 1));

/// Monday-first month grid, one cell per day.
class _MonthGrid extends StatelessWidget {
  final int year;
  final int month;
  final Map<int, int> perDay;
  final int max;
  final DateTime today;
  final int? selected;
  final ValueChanged<int> onSelect;

  const _MonthGrid({
    required this.year,
    required this.month,
    required this.perDay,
    required this.max,
    required this.today,
    required this.selected,
    required this.onSelect,
  });

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = DateUtils.getDaysInMonth(year, month);
    // DateTime.weekday: Mon = 1 .. Sun = 7.
    final lead = DateTime(year, month, 1).weekday - 1;
    final cells = lead + days;
    final rows = (cells / 7).ceil();
    return Column(
      children: [
        Row(
          children: [
            for (final w in _weekdays)
              Expanded(
                child: Center(
                  child: Text(w,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: mutedTextColor(context))),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(child: _cell(context, scheme, r * 7 + c - lead + 1)),
            ],
          ),
      ],
    );
  }

  Widget _cell(BuildContext context, ColorScheme scheme, int day) {
    final days = DateUtils.getDaysInMonth(year, month);
    if (day < 1 || day > days) return const AspectRatio(aspectRatio: 0.85);
    final amount = perDay[day] ?? 0;
    final level = spendLevel(amount, max);
    final date = DateTime(year, month, day);
    final isToday = date == today;
    final isFuture = date.isAfter(today);
    final isSelected = day == selected;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: AspectRatio(
        aspectRatio: 0.85,
        child: Material(
          color: level == 0 ? Colors.transparent : _heat(context, level),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: isSelected
                ? BorderSide(color: scheme.primary, width: 2)
                : isToday
                    ? BorderSide(color: scheme.outline)
                    : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSelect(day),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$day',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isToday ? FontWeight.bold : FontWeight.normal,
                          color: isFuture ? mutedTextColor(context) : null)),
                  if (amount != 0)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(formatMoneyCompact(amount),
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 11, color: mutedTextColor(context));
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('Less', style: muted),
        const SizedBox(width: 4),
        for (var l = 1; l <= 4; l++)
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: _heat(context, l),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        const SizedBox(width: 4),
        Text('More', style: muted),
      ],
    );
  }
}
