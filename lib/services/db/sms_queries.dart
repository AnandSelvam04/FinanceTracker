part of '../db_service.dart';

/// The SMS import's memory: which messages were imported or dismissed.
extension SmsQueries on DBService {
  /// Every sourceRef already accounted for: imported as a transaction, or
  /// dismissed in the review queue. A rescan filters its candidates through
  /// this so neither an imported message nor a rejected one comes back.
  ///
  /// Pass [includeIgnored] as false to leave the dismissal list out, so a
  /// "show dismissed" rescan can surface messages the user rejected earlier
  /// while still hiding ones that are already imported.
  Future<Set<String>> existingSourceRefs({bool includeIgnored = true}) async {
    final db = await database;
    final imported = await db.rawQuery(
        'SELECT ${DbConstants.colSourceRef} AS ref FROM ${DbConstants.tableExpenses} '
        'WHERE ${DbConstants.colSourceRef} IS NOT NULL');
    final ignored = includeIgnored
        ? await db.rawQuery(
            'SELECT ${DbConstants.colSourceRef} AS ref FROM ${DbConstants.tableSmsIgnored}')
        : const <Map<String, Object?>>[];
    return {
      for (final row in [...imported, ...ignored])
        if (row['ref'] is String) row['ref'] as String,
    };
  }

  /// Every message the user dismissed in the review queue, for backups.
  Future<List<String>> ignoredSourceRefs() async {
    final db = await database;
    final rows = await db.query(DbConstants.tableSmsIgnored);
    return [
      for (final r in rows)
        if (r[DbConstants.colSourceRef] is String)
          r[DbConstants.colSourceRef] as String,
    ];
  }

  /// Records that the user dismissed these messages in the review queue.
  Future<void> ignoreSourceRefs(Iterable<String> refs) async {
    if (refs.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final ref in refs) {
        batch.insert(
          DbConstants.tableSmsIgnored,
          {DbConstants.colSourceRef: ref},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Removes these messages from the dismissal list, so importing a message
  /// the user previously dismissed also clears the rejection that was hiding
  /// it from later scans.
  Future<void> unignoreSourceRefs(Iterable<String> refs) async {
    final list = refs.toList(growable: false);
    if (list.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(list.length, '?').join(', ');
    await db.delete(
      DbConstants.tableSmsIgnored,
      where: '${DbConstants.colSourceRef} IN ($placeholders)',
      whereArgs: list,
    );
  }

  Future<void> clearSmsIgnored() async {
    final db = await database;
    await db.delete(DbConstants.tableSmsIgnored);
  }
}
