import '../utils/db_constants.dart';

/// How a rule's text is compared with a transaction's description.
enum RuleMatch {
  /// The text appears in the description at the start of a word: "zomato"
  /// matches "ZOMATO ONLINE" and "UPI-ZOMATOLTD", and "ola" matches
  /// "OLACABS" but not "COCA COLA".
  contains,

  /// The description begins with the text.
  startsWith,

  /// The description is the text and nothing else.
  exact;

  String get label => switch (this) {
        RuleMatch.contains => 'Contains',
        RuleMatch.startsWith => 'Starts with',
        RuleMatch.exact => 'Is exactly',
      };

  static RuleMatch fromName(Object? name) => RuleMatch.values.firstWhere(
        (m) => m.name == name,
        orElse: () => RuleMatch.contains,
      );
}

/// "If the description contains *zomato*, file it under Food and tag it
/// #eatingout."
///
/// A rule is something the user wrote on purpose, so it beats the category
/// recalled from how a merchant was filed last time ([CategoryMemory]) and the
/// guess from its name ([MerchantCategories]). Rules are tried in the order
/// the user put them in; the first that matches wins.
class CategoryRule {
  /// Stable identity, so an edit or a reorder finds the same rule.
  final String id;
  final RuleMatch match;

  /// The text to look for, as the user typed it.
  final String pattern;

  /// [DbConstants.txExpense] or [DbConstants.txIncome]: categories belong to
  /// one or the other, so a rule only ever files rows of its own type.
  /// Refunds count as expenses.
  final String type;
  final String category;

  /// A tag (without its #) added to the note of every row the rule files, or
  /// null for none.
  final String? tag;
  final bool enabled;

  CategoryRule({
    required this.id,
    this.match = RuleMatch.contains,
    required this.pattern,
    this.type = DbConstants.txExpense,
    required this.category,
    String? tag,
    this.enabled = true,
  }) : tag = cleanTag(tag);

  bool get isIncome => type == DbConstants.txIncome;

  /// Whether this rule files a row of [rowType] described as [description].
  /// Disabled rules and transfers never match.
  bool matches(String description, String rowType) {
    if (!enabled || rowType != type) return false;
    final needle = normalise(pattern);
    if (needle.isEmpty) return false;
    final hay = normalise(description);
    if (hay.isEmpty) return false;
    return switch (match) {
      RuleMatch.exact => hay == needle,
      RuleMatch.startsWith => hay.startsWith(needle),
      RuleMatch.contains => ' $hay'.contains(' $needle') ||
          // Bank narrations glue the merchant onto a prefix with no
          // space ("UPI/ZOMATO/…" normalises to "upi zomato", but
          // "POS1234ZOMATO" does not); a needle of five or more
          // characters is specific enough to find anywhere.
          (needle.length >= 5 && hay.contains(needle)),
    };
  }

  /// A short summary for lists: `Contains "zomato"`.
  String get condition => '${match.label} "${pattern.trim()}"';

  /// Lower case, with punctuation as spaces and spaces collapsed, so
  /// "UPI/ZOMATO-LTD", "Zomato Ltd" and "zomato ltd." compare alike. "@"
  /// and "." are kept inside a word for UPI handles ("swiggy@icici").
  static String normalise(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}@.]+', unicode: true), ' ')
      .replaceAll(RegExp(r'(?<!\S)\.+|\.+(?!\S)'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// [raw] as a tag: without a leading #, lower case, spaces as hyphens and
  /// anything a #tag cannot hold dropped. Null when nothing is left.
  static String? cleanTag(String? raw) {
    if (raw == null) return null;
    final t = raw
        .trim()
        .replaceFirst(RegExp(r'^#+'), '')
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^\p{L}\p{N}_-]', unicode: true), '')
        .replaceAll(RegExp(r'^[-_]+|[-_]+$'), '');
    return t.isEmpty ? null : t;
  }

  CategoryRule copyWith({
    RuleMatch? match,
    String? pattern,
    String? type,
    String? category,
    String? tag,
    bool clearTag = false,
    bool? enabled,
  }) =>
      CategoryRule(
        id: id,
        match: match ?? this.match,
        pattern: pattern ?? this.pattern,
        type: type ?? this.type,
        category: category ?? this.category,
        tag: clearTag ? null : (tag ?? this.tag),
        enabled: enabled ?? this.enabled,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'm': match.name,
        'p': pattern,
        't': type,
        'c': category,
        if (tag != null) 'g': tag,
        if (!enabled) 'off': true,
      };

  /// Null for an entry that is damaged or from a build that wrote something
  /// else, so one bad rule never takes the others with it.
  static CategoryRule? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final pattern = json['p'];
    final category = json['c'];
    if (id is! String || pattern is! String || category is! String) {
      return null;
    }
    if (pattern.trim().isEmpty || category.trim().isEmpty) return null;
    final type = json['t'] == DbConstants.txIncome
        ? DbConstants.txIncome
        : DbConstants.txExpense;
    final tag = json['g'];
    return CategoryRule(
      id: id,
      match: RuleMatch.fromName(json['m']),
      pattern: pattern,
      type: type,
      category: category,
      tag: tag is String ? tag : null,
      enabled: json['off'] != true,
    );
  }
}
