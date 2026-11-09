part of '../expense_list_screen.dart';

/// The Transactions list's advanced filters. A null field means "any".
typedef _AdvancedFilters = ({
  String? category,
  int? accountId,
  int? minAmount,
  int? maxAmount,
  DateTimeRange? range,
});

String _fmtRange(DateTimeRange r) =>
    '${formatShortDate(r.start)} → ${formatShortDate(r.end)}';

/// Bottom sheet for the advanced filters. Edits a working copy and pops it
/// on Apply (or an all-clear one on Reset all), so nothing changes until the
/// user confirms; dismissing the sheet pops null.
class _FilterSheet extends StatefulWidget {
  final List<String> categories;
  final List<Account> accounts;
  final DateTime firstDate;
  final _AdvancedFilters initial;

  const _FilterSheet({
    required this.categories,
    required this.accounts,
    required this.firstDate,
    required this.initial,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _category = widget.initial.category;
  late int? _accountId = widget.initial.accountId;
  late DateTimeRange? _range = widget.initial.range;
  late final _min = TextEditingController(
      text: widget.initial.minAmount == null
          ? ''
          : minorToEditString(widget.initial.minAmount!));
  late final _max = TextEditingController(
      text: widget.initial.maxAmount == null
          ? ''
          : minorToEditString(widget.initial.maxAmount!));

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.categories;
    final accounts = widget.accounts;
    final range = _range;
    return Padding(
      padding: bottomSheetPadding(context),
      // Scrollable so the filter list can still be reached (and Apply
      // tapped) when the keyboard shrinks the available height.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filters', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              isExpanded: true,
              initialValue: categories.contains(_category) ? _category : null,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                DropdownMenuItem<String?>(
                    value: null, child: const Text('Any')),
                ...categories.map((c) => DropdownMenuItem<String?>(
                    value: c, child: Text(c, overflow: TextOverflow.ellipsis))),
              ],
              onChanged: (v) => setState(() => _category = v),
            ),
            const SizedBox(height: 12),
            if (accounts.isNotEmpty) ...[
              DropdownButtonFormField<int?>(
                isExpanded: true,
                initialValue:
                    accounts.any((a) => a.id == _accountId) ? _accountId : null,
                decoration: const InputDecoration(labelText: 'Account'),
                items: [
                  DropdownMenuItem<int?>(value: null, child: const Text('Any')),
                  ...accounts.map((a) => DropdownMenuItem<int?>(
                      value: a.id,
                      child: Text(a.name, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _min,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Min amount'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _max,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Max amount'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(range == null
                      ? 'Date range: uses Year/Month above'
                      : 'Date range: ${_fmtRange(range)}'),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: widget.firstDate,
                      lastDate: DateTime.now(),
                      initialDateRange: _range,
                    );
                    if (picked != null) setState(() => _range = picked);
                  },
                  child: const Text('Pick'),
                ),
                if (range != null)
                  TextButton(
                    onPressed: () => setState(() => _range = null),
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop<_AdvancedFilters>(context, (
                    category: null,
                    accountId: null,
                    minAmount: null,
                    maxAmount: null,
                    range: null,
                  )),
                  child: const Text('Reset all'),
                ),
                const Spacer(),
                SizedBox(
                  height: kSheetActionHeight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop<_AdvancedFilters>(context, (
                      category: _category,
                      accountId: _accountId,
                      minAmount: parseMinor(_min.text.trim()),
                      maxAmount: parseMinor(_max.text.trim()),
                      range: _range,
                    )),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
