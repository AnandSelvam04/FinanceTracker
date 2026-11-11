import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';
import 'db_constants.dart';

/// Built-in categories offered before the user has any of their own.
const defaultExpenseCategories = [
  'Food',
  'Transport',
  'Shopping',
  'Bills',
  'Entertainment',
  'Health',
  'Education',
  'Other',
];

const defaultIncomeCategories = [
  'Salary',
  'Business',
  'Interest',
  'Dividends',
  'Gift',
  'Refund',
  'Other',
];

/// Icons a category can be given, by a stable key that is what gets stored.
///
/// A fixed const set rather than raw code points: release builds tree-shake
/// the icon font and refuse an [IconData] built at run time.
const Map<String, IconData> categoryIconChoices = {
  'restaurant': Icons.restaurant,
  'cafe': Icons.local_cafe,
  'grocery': Icons.local_grocery_store,
  'shopping': Icons.shopping_bag,
  'clothes': Icons.checkroom,
  'home': Icons.home,
  'bolt': Icons.bolt,
  'water': Icons.water_drop,
  'phone': Icons.smartphone,
  'wifi': Icons.wifi,
  'bills': Icons.receipt_long,
  'bus': Icons.directions_bus,
  'car': Icons.directions_car,
  'bike': Icons.two_wheeler,
  'fuel': Icons.local_gas_station,
  'flight': Icons.flight,
  'hotel': Icons.hotel,
  'movie': Icons.movie,
  'music': Icons.music_note,
  'game': Icons.sports_esports,
  'subscriptions': Icons.subscriptions,
  'health': Icons.favorite,
  'medical': Icons.local_hospital,
  'pharmacy': Icons.medication,
  'fitness': Icons.fitness_center,
  'school': Icons.school,
  'book': Icons.menu_book,
  'kids': Icons.child_care,
  'pets': Icons.pets,
  'gift': Icons.card_giftcard,
  'charity': Icons.volunteer_activism,
  'beauty': Icons.spa,
  'tools': Icons.build,
  'insurance': Icons.verified_user,
  'tax': Icons.account_balance,
  'work': Icons.work,
  'salary': Icons.payments,
  'savings': Icons.savings,
  'trending': Icons.trending_up,
  'refund': Icons.assignment_return,
  'trophy': Icons.emoji_events,
  'celebration': Icons.celebration,
  'label': Icons.label,
  'category': Icons.category,
};

/// One category the user created, restyled or hid.
class CustomCategory {
  final String name;

  /// Key into [categoryIconChoices]; null keeps the automatic icon.
  final String? icon;

  /// ARGB colour; null keeps the automatic colour.
  final int? color;

  /// A built-in category the user removed from the pickers.
  final bool hidden;

  const CustomCategory(this.name, {this.icon, this.color, this.hidden = false});

  Map<String, Object?> toJson() => {
        'n': name,
        if (icon != null) 'i': icon,
        if (color != null) 'c': color,
        if (hidden) 'h': true,
      };

  static CustomCategory? fromJson(Object? json) {
    if (json is! Map || json['n'] is! String) return null;
    final icon = json['i'];
    final color = json['c'];
    return CustomCategory(
      json['n'] as String,
      icon: icon is String && categoryIconChoices.containsKey(icon)
          ? icon
          : null,
      color: color is int ? color : null,
      hidden: json['h'] == true,
    );
  }
}

/// The user's own categories and the icon and colour they gave any category.
///
/// Categories are otherwise just the text on a transaction, so one that has
/// no transactions yet, or a look chosen for one, has nowhere else to live.
/// Kept in preferences as one JSON string (and carried in backups with the
/// other settings) rather than in the database: it is presentation, and
/// nothing in the ledger depends on it.
///
/// A singleton because `categoryIcon` and `CategoryColors.forCategory` are
/// called from everywhere, including charts and PDF code with no context.
class CategoryStore extends ChangeNotifier {
  CategoryStore._();
  static final CategoryStore instance = CategoryStore._();

  static const prefsKey = 'customCategories';

  final Map<String, List<CustomCategory>> _byType = {
    DbConstants.txExpense: [],
    DbConstants.txIncome: [],
  };

  static String _norm(String name) => name.trim().toLowerCase();

  List<CustomCategory> _list(String type) =>
      _byType[type] ?? _byType[DbConstants.txExpense]!;

  /// Reads the saved categories. Safe to call again (after a restore).
  Future<void> load() async {
    for (final list in _byType.values) {
      list.clear();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final json = jsonDecode(raw);
        if (json is Map) {
          for (final type in _byType.keys) {
            final rows = json[type];
            if (rows is! List) continue;
            for (final row in rows) {
              final c = CustomCategory.fromJson(row);
              if (c != null && c.name.trim().isNotEmpty) _byType[type]!.add(c);
            }
          }
        }
      }
    } catch (e, st) {
      // A damaged entry only loses the custom looks, never a transaction.
      AppLogger.error('Could not read custom categories', e, st);
    }
    notifyListeners();
  }

  Future<void> _save() async {
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        prefsKey,
        jsonEncode({
          for (final e in _byType.entries)
            e.key: [for (final c in e.value) c.toJson()],
        }));
  }

  CustomCategory? _find(String type, String name) {
    final key = _norm(name);
    for (final c in _list(type)) {
      if (_norm(c.name) == key) return c;
    }
    return null;
  }

  /// The look given to [name] under either type, if any.
  CustomCategory? _styleOf(String name) {
    final key = _norm(name);
    for (final list in _byType.values) {
      for (final c in list) {
        if (!c.hidden && _norm(c.name) == key) return c;
      }
    }
    return null;
  }

  /// The icon chosen for [name], or null to use the automatic one.
  IconData? iconFor(String name) {
    if (_byType.values.every((l) => l.isEmpty)) return null;
    return categoryIconChoices[_styleOf(name)?.icon];
  }

  /// The colour chosen for [name], or null to use the automatic one.
  Color? colorFor(String name) {
    if (_byType.values.every((l) => l.isEmpty)) return null;
    final value = _styleOf(name)?.color;
    return value == null ? null : Color(value);
  }

  /// The stored entry for [name], when the user created or restyled it.
  CustomCategory? entry(String type, String name) => _find(type, name);

  bool isHidden(String type, String name) =>
      _find(type, name)?.hidden ?? false;

  static List<String> builtIn(String type) => type == DbConstants.txIncome
      ? defaultIncomeCategories
      : defaultExpenseCategories;

  static bool isBuiltIn(String type, String name) =>
      builtIn(type).any((c) => _norm(c) == _norm(name));

  /// Categories to offer in a picker for [type]: the user's own first, then
  /// the built-in ones they have not removed.
  List<String> offered(String type) {
    final seen = <String>{};
    return [
      for (final c in _list(type))
        if (!c.hidden && seen.add(_norm(c.name))) c.name,
      for (final c in builtIn(type))
        if (!isHidden(type, c) && seen.add(_norm(c))) c,
    ];
  }

  /// Adds (or restyles, or un-hides) the category [name].
  Future<void> put(String type, String name,
      {String? icon, int? color}) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    final list = _list(type);
    final existing = _find(type, clean);
    final next = CustomCategory(existing?.name ?? clean, icon: icon, color: color);
    if (existing == null) {
      list.add(next);
    } else {
      list[list.indexOf(existing)] = next;
    }
    await _save();
  }

  /// Makes sure [name] is offered in pickers, keeping any look it has.
  Future<void> ensure(String type, String name) async {
    final existing = _find(type, name);
    if (existing != null && !existing.hidden) return;
    if (existing == null && isBuiltIn(type, name)) return;
    await put(type, name);
  }

  /// Carries [from]'s entry over to [to] after a rename; after a merge into
  /// an existing category ([merged]) it is simply dropped, so the target
  /// keeps its own look.
  Future<void> rename(String type, String from, String to,
      {required bool merged}) async {
    final list = _list(type);
    final existing = _find(type, from);
    if (existing != null) list.remove(existing);
    if (!merged) {
      final target = _find(type, to);
      if (target != null) list.remove(target);
      // A built-in name that was renamed away must not come back as a chip.
      if (isBuiltIn(type, from) && _norm(from) != _norm(to)) {
        list.add(CustomCategory(from, hidden: true));
      }
      if (existing != null && !existing.hidden) {
        list.add(CustomCategory(to.trim(),
            icon: existing.icon, color: existing.color));
      } else if (!isBuiltIn(type, to)) {
        list.add(CustomCategory(to.trim()));
      }
    } else if (isBuiltIn(type, from)) {
      list.add(CustomCategory(from, hidden: true));
    }
    await _save();
  }

  /// Stops offering [name]: a category of the user's is forgotten, a built-in
  /// one is hidden.
  Future<void> remove(String type, String name) async {
    final list = _list(type);
    final existing = _find(type, name);
    if (existing != null) list.remove(existing);
    if (isBuiltIn(type, name)) list.add(CustomCategory(name, hidden: true));
    await _save();
  }
}
