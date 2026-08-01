import '../utils/db_constants.dart';

/// What category you last filed a given merchant under.
///
/// Imported rows would otherwise all arrive as "Other", so every scan would
/// mean setting a category on every row forever. Learning it from the
/// transactions already in the ledger turns the common case into "glance,
/// tap Import".
///
/// Pure Dart and built from plain rows, so the matching rules are testable
/// without a database.
class CategoryMemory {
  final Map<String, String> _byMerchant;

  const CategoryMemory(this._byMerchant);

  const CategoryMemory.empty() : _byMerchant = const {};

  bool get isEmpty => _byMerchant.isEmpty;

  /// Builds the map from `(description, category, n, lastDate)` rows as
  /// produced by [DBService.merchantCategoryCounts].
  ///
  /// Rows are expected newest-and-most-used first; the first row seen for a
  /// merchant wins, so ordering is the caller's contract rather than something
  /// re-derived here.
  factory CategoryMemory.fromRows(List<Map<String, Object?>> rows) {
    final map = <String, String>{};
    for (final row in rows) {
      final description = row[DbConstants.colDescription];
      final category = row[DbConstants.colCategory];
      if (description is! String || category is! String) continue;
      if (category.trim().isEmpty) continue;
      final key = merchantKey(description);
      if (key.isEmpty) continue;
      map.putIfAbsent(key, () => category);
    }
    return CategoryMemory(map);
  }

  /// The category last used for [description], or null if it is unfamiliar.
  String? categoryFor(String description) {
    final key = merchantKey(description);
    if (key.isEmpty) return null;
    return _byMerchant[key];
  }

  /// Normalises a merchant so trivial differences between how a bank writes it
  /// and how you typed it still match: case, surrounding punctuation, repeated
  /// spaces, and the reference digits banks append ("SWIGGY 1234").
  static String merchantKey(String description) {
    final cleaned = description
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9@. ]'), ' ')
        // A trailing run of digits is a transaction reference, not part of the
        // name — keep "SWIGGY" and "SWIGGY 88213" together.
        .replaceAll(RegExp(r'\s+\d+\s*$'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Dots are kept inside a name ("H.D.F.C", "merchant@ybl") but a leading or
    // trailing one is just sentence punctuation the bank wrapped it in.
    return cleaned.replaceAll(RegExp(r'^\.+|\.+$'), '').trim();
  }
}
