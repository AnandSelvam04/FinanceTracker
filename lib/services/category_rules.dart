import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/category_rule.dart';
import '../models/expense.dart';
import '../utils/app_logger.dart';
import '../utils/tags.dart';

/// One row a rule would change: its new category and note, and the old ones
/// so the change can be undone.
class RuleChange {
  final Expense row;
  final CategoryRule rule;
  final String category;
  final String? note;

  const RuleChange(this.row, this.rule, this.category, this.note);

  /// The same row put back as it was.
  RuleChange get reverted => RuleChange(row, rule, row.category, row.note);
}

/// Matching rules against transactions. Pure Dart, so it is testable without
/// preferences or a database.
class CategoryRules {
  CategoryRules._();

  /// The first rule in [rules] that files a [type] row described as
  /// [description], or null when none does. Rules are tried in order.
  static CategoryRule? firstMatch(
      List<CategoryRule> rules, String description, String type) {
    for (final r in rules) {
      if (r.matches(description, type)) return r;
    }
    return null;
  }

  /// The type a row is filed under for rules: refunds are expenses, and a
  /// transfer has none (its category is fixed).
  static String? typeOf(Expense e) => e.isTransfer ? null : e.type;

  /// [note] with `#tag` added at the end, unless it already carries that tag.
  /// Null [tag] returns [note] unchanged.
  static String? noteWithTag(String? note, String? tag) {
    if (tag == null || tag.isEmpty) return note;
    if (tagsIn(note).contains(tag)) return note;
    final trimmed = note?.trim() ?? '';
    return trimmed.isEmpty ? '#$tag' : '$trimmed #$tag';
  }

  /// What [rule] would change on [e], or null when it does not match or the
  /// row already reads that way.
  static RuleChange? changeFor(Expense e, CategoryRule rule) {
    final type = typeOf(e);
    if (type == null || !rule.matches(e.description, type)) return null;
    final note = noteWithTag(e.note, rule.tag);
    final sameCategory =
        e.category.trim().toLowerCase() == rule.category.trim().toLowerCase();
    if (sameCategory && note == e.note) return null;
    return RuleChange(e, rule, rule.category, note);
  }

  /// The changes running [rules] over [rows] would make, each row taking its
  /// first matching rule. With [only] set, just that rule is run (as from its
  /// own "Apply to past" button) — though a row an earlier rule claims is
  /// still left to that earlier rule.
  static List<RuleChange> changes(List<CategoryRule> rules, List<Expense> rows,
      {CategoryRule? only}) {
    final out = <RuleChange>[];
    for (final e in rows) {
      final type = typeOf(e);
      if (type == null) continue;
      final rule = firstMatch(rules, e.description, type);
      if (rule == null) continue;
      if (only != null && rule.id != only.id) continue;
      final change = changeFor(e, rule);
      if (change != null) out.add(change);
    }
    return out;
  }

  /// The rows [rule] matches at all, whether or not it would change them.
  static List<Expense> matching(CategoryRule rule, List<Expense> rows) => [
        for (final e in rows)
          if (typeOf(e) case final t? when rule.matches(e.description, t)) e,
      ];

  /// The text a rule built from the description [description] should look
  /// for: the description in lower case, without the reference number a
  /// bank appends ("SWIGGY 88213" → "swiggy").
  static String patternFrom(String description) =>
      CategoryRule.normalise(description.replaceAll(RegExp(r'\s+\d+\s*$'), ''))
          .trim();
}

/// The user's rules, in their order, kept in preferences as one JSON list and
/// carried in backups with the other settings (like `CategoryStore`).
///
/// A singleton so the importers and the Add screen can read the rules without
/// a [BuildContext].
class CategoryRuleStore extends ChangeNotifier {
  CategoryRuleStore._();
  static final CategoryRuleStore instance = CategoryRuleStore._();

  static const prefsKey = 'categoryRules';

  final List<CategoryRule> _rules = [];

  /// Every rule, in the order they are tried.
  List<CategoryRule> get rules => List.unmodifiable(_rules);

  /// The first enabled rule that files a [type] row described as
  /// [description].
  CategoryRule? firstMatch(String description, String type) =>
      CategoryRules.firstMatch(_rules, description, type);

  CategoryRule? byId(String id) {
    for (final r in _rules) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Reads the saved rules. Safe to call again (after a restore).
  Future<void> load() async {
    _rules.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final json = jsonDecode(raw);
        if (json is List) {
          final seen = <String>{};
          for (final row in json) {
            final r = CategoryRule.fromJson(row);
            if (r != null && seen.add(r.id)) _rules.add(r);
          }
        }
      }
    } catch (e, st) {
      // A damaged list only loses the rules, never a transaction.
      AppLogger.error('Could not read category rules', e, st);
    }
    notifyListeners();
  }

  Future<void> _save() async {
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        prefsKey, jsonEncode([for (final r in _rules) r.toJson()]));
  }

  /// A fresh id for a new rule.
  static String newId() =>
      'r${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  /// Adds [rule] at the end, or at [index] when given.
  Future<void> add(CategoryRule rule, {int? index}) async {
    _rules.removeWhere((r) => r.id == rule.id);
    if (index == null || index < 0 || index > _rules.length) {
      _rules.add(rule);
    } else {
      _rules.insert(index, rule);
    }
    await _save();
  }

  /// Replaces the rule with [rule]'s id, keeping its place.
  Future<void> update(CategoryRule rule) async {
    final i = _rules.indexWhere((r) => r.id == rule.id);
    if (i == -1) {
      _rules.add(rule);
    } else {
      _rules[i] = rule;
    }
    await _save();
  }

  /// Removes the rule [id]. Returns where it was, for undo, or -1.
  Future<int> remove(String id) async {
    final i = _rules.indexWhere((r) => r.id == id);
    if (i == -1) return -1;
    _rules.removeAt(i);
    await _save();
    return i;
  }

  /// Moves the rule at [from] so it ends up at index [to].
  Future<void> reorder(int from, int to) async {
    if (from < 0 || from >= _rules.length || from == to) return;
    final rule = _rules.removeAt(from);
    _rules.insert(to.clamp(0, _rules.length), rule);
    await _save();
  }

  /// A category of [type] was renamed (or merged) from [from] to [to]: every
  /// rule filing into it follows. Returns how many changed.
  Future<int> renameCategory(String type, String from, String to) async {
    final key = from.trim().toLowerCase();
    var changed = 0;
    for (var i = 0; i < _rules.length; i++) {
      final r = _rules[i];
      if (r.type == type && r.category.trim().toLowerCase() == key) {
        _rules[i] = r.copyWith(category: to.trim());
        changed++;
      }
    }
    if (changed > 0) await _save();
    return changed;
  }

  /// Forgets every rule (tests).
  @visibleForTesting
  Future<void> clear() async {
    _rules.clear();
    await _save();
  }
}
