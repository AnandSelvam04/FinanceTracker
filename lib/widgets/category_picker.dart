import 'package:flutter/material.dart';

import '../services/db_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_logger.dart';
import '../utils/category_store.dart';
import '../utils/db_constants.dart';
import '../utils/insets.dart';
import 'category_avatar.dart';
import 'category_choice_chip.dart';
import '../utils/font_sizes.dart';
import '../utils/dimens.dart';

/// Chips for choosing a transaction's category, ending in a **More** chip
/// that opens the full, searchable list.
///
/// The category used to be a free-text field, so "Grocery" typed once next to
/// "Groceries" quietly became a second category with its own budget and chart
/// slice. Here a category is always picked; a new one is made on purpose,
/// from the list, where the existing ones are in view.
class CategoryPickerField extends StatelessWidget {
  /// [DbConstants.txExpense] or [DbConstants.txIncome].
  final String type;

  /// The chosen category, or empty when none is.
  final String value;

  /// Categories to show as chips, most useful first.
  final List<String> suggestions;
  final ValueChanged<String> onChanged;

  /// Shown under the chips (a form's validation message).
  final String? errorText;

  const CategoryPickerField({
    super.key,
    required this.type,
    required this.value,
    required this.suggestions,
    required this.onChanged,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final income = type == DbConstants.txIncome;
    final chosen = value.trim();
    // A category picked from the full list (or carried in by a copy, a scan
    // or voice) that is not among the chips still has to show as selected.
    final chips = [
      if (chosen.isNotEmpty &&
          !suggestions.any((c) => isSameCategory(c, chosen)))
        chosen,
      ...suggestions,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(income ? 'Source' : 'Category',
            style: TextStyle(
                fontSize: FontSizes.caption, color: mutedTextColor(context))),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final c in chips)
              CategoryChoiceChip(
                category: c,
                selected: isSameCategory(chosen, c),
                onSelected: () => onChanged(c),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('More'),
              tooltip: income
                  ? 'All sources, or add a new one'
                  : 'All categories, or add a new one',
              onPressed: () async {
                final picked = await showCategoryPicker(context,
                    type: type, selected: chosen, suggestions: suggestions);
                if (picked != null) onChanged(picked);
              },
            ),
          ],
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(errorText!,
                style: TextStyle(
                    fontSize: FontSizes.caption,
                    color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }
}

/// A form row showing the chosen category; tapping it opens the full list.
/// For sheets too tight for a wrap of chips (the transaction editor).
class CategoryPickerTile extends StatelessWidget {
  final String type;
  final String value;
  final ValueChanged<String> onChanged;

  /// Overrides the field's label ("Category", or "Source" for income).
  final String? label;

  /// Compact, for a row that shares its line with another field.
  final bool dense;

  /// Shown under the field (a form's validation message).
  final String? errorText;

  const CategoryPickerTile({
    super.key,
    required this.type,
    required this.value,
    required this.onChanged,
    this.label,
    this.dense = false,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final income = type == DbConstants.txIncome;
    return InkWell(
      onTap: () async {
        final picked =
            await showCategoryPicker(context, type: type, selected: value);
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label ?? (income ? 'Source' : 'Category'),
          isDense: dense,
          errorText: errorText,
          suffixIcon: const Icon(Icons.arrow_drop_down),
          suffixIconConstraints:
              dense ? const BoxConstraints(minWidth: 28, minHeight: 28) : null,
        ),
        child: Row(
          children: [
            if (value.trim().isNotEmpty) ...[
              CategoryAvatar(category: value, radius: dense ? 10 : 12),
              const SizedBox(width: Space.sm),
            ],
            Expanded(
              child: Text(value.trim().isEmpty ? 'Choose' : value,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the searchable list of every category of [type] — the user's own,
/// the ones their transactions use and the built-in ones — with a row to
/// create the name typed when nothing matches. Returns the category picked,
/// or null when the sheet is dismissed.
Future<String?> showCategoryPicker(
  BuildContext context, {
  required String type,
  String selected = '',
  List<String> suggestions = const [],
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CategoryPickerSheet(
        type: type, selected: selected, suggestions: suggestions),
  );
}

class _CategoryPickerSheet extends StatefulWidget {
  final String type;
  final String selected;
  final List<String> suggestions;
  const _CategoryPickerSheet({
    required this.type,
    required this.selected,
    required this.suggestions,
  });

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  final _search = TextEditingController();
  List<String> _used = const [];

  bool get _income => widget.type == DbConstants.txIncome;

  @override
  void initState() {
    super.initState();
    _loadUsed();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadUsed() async {
    try {
      final usage = await DBService().categoryUsage(widget.type);
      if (mounted) setState(() => _used = [for (final u in usage) u.category]);
    } catch (e, st) {
      // The list still offers the suggestions and the user's own categories.
      AppLogger.error('Could not list the categories in use', e, st);
    }
  }

  /// Every category on offer, de-duplicated ignoring case, the first spelling
  /// seen winning.
  List<String> get _all {
    final seen = <String>{};
    return [
      for (final c in [
        ...widget.suggestions,
        ..._used,
        ...CategoryStore.instance.offered(widget.type),
      ])
        if (c.trim().isNotEmpty && seen.add(c.trim().toLowerCase())) c.trim(),
    ];
  }

  Future<void> _create(String name) async {
    final navigator = Navigator.of(context);
    await CategoryStore.instance.ensure(widget.type, name);
    navigator.pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    final all = _all;
    final matches = query.isEmpty
        ? all
        : [
            for (final c in all)
              if (c.toLowerCase().contains(query.toLowerCase())) c,
          ];
    final exact = all.any((c) => isSameCategory(c, query));
    return Padding(
      padding: bottomSheetPadding(context),
      child: SizedBox(
        // Tall enough to browse, short enough that the form behind stays in
        // view; the padding above lifts it clear of the keyboard.
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_income ? 'Income source' : 'Category',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Space.md),
            TextField(
              controller: _search,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: _income
                    ? 'Search, or type a new source'
                    : 'Search, or type a new category',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Space.sm),
            Expanded(
              child: ListView(
                children: [
                  if (query.isNotEmpty && !exact)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(Icons.add,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer),
                      ),
                      title: Text('Create "$query"'),
                      subtitle: matches.isEmpty
                          ? null
                          : const Text('Or pick one below'),
                      onTap: () => _create(query),
                    ),
                  for (final c in matches)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CategoryAvatar(category: c),
                      title: Text(c),
                      trailing: isSameCategory(c, widget.selected)
                          ? Icon(Icons.check,
                              color: Theme.of(context).colorScheme.primary)
                          : null,
                      onTap: () => Navigator.pop(context, c),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
