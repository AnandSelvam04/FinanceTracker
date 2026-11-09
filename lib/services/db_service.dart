import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import '../models/account.dart';
import '../models/emi_plan.dart';
import '../models/expense.dart';
import '../models/investment.dart';
import '../models/budget.dart';
import '../models/net_worth_point.dart';
import '../models/recurring_rule.dart';
import '../models/savings_goal.dart';
import '../models/tx_template.dart';
import '../utils/app_logger.dart';
import '../utils/category_suggestions.dart';
import '../utils/currency_format.dart';
import '../utils/db_constants.dart';
import 'db/db_schema.dart';

part 'db/account_queries.dart';
part 'db/budget_queries.dart';
part 'db/expense_queries.dart';
part 'db/goal_queries.dart';
part 'db/investment_queries.dart';
part 'db/recurring_queries.dart';
part 'db/sms_queries.dart';

class DBService {
  static final DBService _instance = DBService._internal();
  factory DBService() => _instance;
  DBService._internal();

  /// Test-only hook so tests can point the singleton at an isolated file.
  static String? dbNameOverride;

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const _kEncEnabledFlag = 'db_encryption_enabled';
  static const _kEncKey = 'db_encryption_key';

  /// The in-flight or completed open. Cached as a future, not a [Database],
  /// so callers that race on a cold start (the dashboard fires several loads
  /// in the same frame) share one open instead of each running [_initDB] and
  /// its secure-storage reads. A failed open is dropped so the next access
  /// retries instead of rethrowing the stale error forever.
  Future<Database>? _db;

  Future<Database> get database {
    final pending = _db;
    if (pending != null) return pending;
    final opening = _initDB();
    _db = opening;
    opening.catchError((Object _) {
      // Only forget this open if nothing has replaced it since.
      if (identical(_db, opening)) _db = null;
      return opening;
    }).ignore();
    return opening;
  }

  /// Closes the database so the next access re-opens it (used by the
  /// encryption migration to switch the file's cipher state).
  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db == null) return;
    final Database open;
    try {
      open = await db;
    } catch (_) {
      return; // The open failed; there is nothing to close.
    }
    await open.close();
  }

  /// Whether the on-device database is currently encrypted. Always false in
  /// test mode.
  ///
  /// A secure-storage read can fail transiently (keystore not yet unlocked
  /// after boot, for one). Treating that as "encryption is off" is a lie that
  /// used to propagate silently: Settings showed the toggle off, and the
  /// backup paths wrote plaintext. It still reports false so the UI has
  /// something to render, but the failure is logged and
  /// [readEncryptionFlagOrThrow] gives the paths that must not guess a way to
  /// tell the two apart.
  Future<bool> isEncryptionEnabled() async {
    if (testFactory != null || dbNameOverride != null) return false;
    try {
      return await readEncryptionFlagOrThrow();
    } catch (e) {
      AppLogger.error(
          'Could not read the encryption flag from secure storage; '
          'reporting encryption as off',
          e);
      return false;
    }
  }

  /// Reads the encryption flag, propagating a secure-storage failure instead
  /// of collapsing it into `false`.
  Future<bool> readEncryptionFlagOrThrow() async {
    if (testFactory != null || dbNameOverride != null) return false;
    return (await _secureStorage.read(key: _kEncEnabledFlag)) == 'true';
  }

  /// Password to open the database: the stored key when encryption is on,
  /// otherwise null (plaintext).
  ///
  /// Only the *flag read* is guarded, so the plain path still works on a host
  /// without secure storage (unit tests, desktop). Once we know encryption is
  /// on, a failure to fetch the key is fatal and propagates — returning null
  /// there would try to open an encrypted file with no key and surface as an
  /// unintelligible SQLite error.
  Future<String?> _password() async {
    if (dbNameOverride != null) return null;
    bool enabled;
    try {
      enabled = await readEncryptionFlagOrThrow();
    } catch (e) {
      AppLogger.error(
          'Secure storage unavailable; opening the database unencrypted', e);
      return null;
    }
    return enabled ? await _getOrCreateKey() : null;
  }

  /// The device-held database key when at-rest encryption is on, otherwise
  /// null. Used to protect the automatic local backup with the same key, so
  /// enabling DB encryption doesn't leave a readable JSON copy on disk.
  ///
  /// Throws if encryption is on but the key can't be read: callers use this to
  /// decide whether to encrypt a backup, and a null there would quietly write
  /// the plaintext copy this exists to prevent.
  Future<String?> deviceKeyIfEncrypted() async {
    if (!await readEncryptionFlagOrThrow()) return null;
    return _getOrCreateKey();
  }

  Future<String> _getOrCreateKey() async {
    var key = await _secureStorage.read(key: _kEncKey);
    if (key == null || key.isEmpty) {
      final rnd = Random.secure();
      key = base64Url.encode(List<int>.generate(32, (_) => rnd.nextInt(256)));
      await _secureStorage.write(key: _kEncKey, value: key);
    }
    return key;
  }

  /// A [DatabaseFactory] injected by tests so the suite runs on
  /// sqflite_common_ffi. Production leaves this null and uses the SQLCipher
  /// factory (with the encryption password) directly. Necessary because
  /// sqflite_sqlcipher's top-level functions hit the native method channel and
  /// ignore the ffi factory tests install globally.
  static DatabaseFactory? testFactory;

  Future<Database> _initDB() async {
    final factory = testFactory;
    if (factory != null) {
      // Test path: plaintext, driven by the injected ffi factory.
      final path = join(await factory.getDatabasesPath(),
          dbNameOverride ?? DbConstants.dbName);
      return factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: DbConstants.dbVersion,
          onCreate: DbSchema.onCreate,
          onUpgrade: DbSchema.onUpgrade,
        ),
      );
    }
    // Production path: SQLCipher; encrypted when the user has opted in.
    final path = join(await getDatabasesPath(), DbConstants.dbName);
    return openDatabase(
      path,
      password: await _password(),
      version: DbConstants.dbVersion,
      onCreate: DbSchema.onCreate,
      onUpgrade: DbSchema.onUpgrade,
    );
  }

  Future<void> clearAll() async {
    await clearExpenses();
    await clearInvestments();
    await clearBudgets();
    await clearAccounts();
    await clearRecurringRules();
    await clearTemplates();
    await clearGoals();
    await (await database).delete(DbConstants.tableEmiPlans);
    // Wiping the ledger has to drop the dismissal list too, or messages the
    // user rejected stay suppressed against a database that no longer has the
    // transactions they were rejected next to.
    await clearSmsIgnored();
  }

  /// Atomically replaces (or, when [clearFirst] is false, appends to) the
  /// database contents with [rowsByTable]. Runs inside one transaction so an
  /// interrupted or failing restore rolls back to the pre-restore state
  /// instead of leaving a wiped, half-filled database.
  Future<void> replaceAllData(
    Map<String, List<Map<String, Object?>>> rowsByTable, {
    bool clearFirst = true,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      if (clearFirst) {
        for (final table in _allTables) {
          await txn.delete(table);
        }
      }
      final batch = txn.batch();
      for (final table in _allTables) {
        for (final row in rowsByTable[table] ?? const []) {
          // The dismissal list and the market values are keyed: merging a
          // backup into data that already holds a key must not abort the
          // restore (a value from the backup wins).
          batch.insert(table, row,
              conflictAlgorithm: switch (table) {
                DbConstants.tableSmsIgnored => ConflictAlgorithm.ignore,
                DbConstants.tableInvestmentValues => ConflictAlgorithm.replace,
                _ => null,
              });
        }
      }
      await batch.commit(noResult: true);
    });
  }

  // --- At-rest encryption (opt-in) -----------------------------------------

  static const List<String> _allTables = [
    DbConstants.tableAccounts,
    DbConstants.tableExpenses,
    DbConstants.tableInvestments,
    DbConstants.tableBudgets,
    DbConstants.tableRecurringRules,
    DbConstants.tableTemplates,
    DbConstants.tableGoals,
    DbConstants.tableEmiPlans,
    // Included so toggling at-rest encryption (which copies every table into a
    // fresh database) carries the dismissal list across. Backups carry it
    // from v7; restoring an older one empties it, and the only cost is that
    // previously dismissed messages reappear once in the review queue.
    DbConstants.tableSmsIgnored,
    DbConstants.tableInvestmentValues,
  ];

  Future<Map<String, List<Map<String, Object?>>>> _dumpAllTables(
      Database db) async {
    final out = <String, List<Map<String, Object?>>>{};
    for (final t in _allTables) {
      out[t] = await db.query(t);
    }
    return out;
  }

  Future<void> _restoreAllTables(
      Database db, Map<String, List<Map<String, Object?>>> data) async {
    final batch = db.batch();
    for (final t in _allTables) {
      for (final row in data[t] ?? const []) {
        batch.insert(t, row);
      }
    }
    await batch.commit(noResult: true);
  }

  bool _sameCounts(Map<String, List<Object?>> a, Map<String, List<Object?>> b) {
    for (final t in _allTables) {
      if ((a[t]?.length ?? 0) != (b[t]?.length ?? 0)) return false;
    }
    return true;
  }

  Future<String> get _snapshotPath async =>
      join(await getDatabasesPath(), 'finance_pre_migration.json');

  Future<void> _writeSafetySnapshot(
      Map<String, List<Map<String, Object?>>> data) async {
    await File(await _snapshotPath).writeAsString(jsonEncode(data));
  }

  /// Removes the plaintext pre-migration snapshot once a cipher migration has
  /// been verified, so no readable copy of the data is left on disk.
  Future<void> _deleteSafetySnapshot() async {
    try {
      final file = File(await _snapshotPath);
      if (await file.exists()) await file.delete();
    } catch (e) {
      AppLogger.error('Failed to delete pre-migration snapshot', e);
    }
  }

  /// Test hook exercising the table dump→restore copy used by the migration,
  /// so the copy logic is covered without real encryption/secure storage.
  Future<void> debugRoundTripTables() async {
    final db = await database;
    final snapshot = await _dumpAllTables(db);
    await clearAll();
    await _restoreAllTables(db, snapshot);
  }

  /// Encrypts the on-device database in place. Safe by construction: writes a
  /// JSON safety snapshot, copies all rows into a fresh encrypted database,
  /// verifies row counts, and rolls back to plaintext on any failure so data
  /// is never lost.
  Future<void> enableEncryption() async {
    if (testFactory != null || dbNameOverride != null) {
      throw Exception('Encryption is not available in test mode');
    }
    if (await isEncryptionEnabled()) return;
    final snapshot = await _dumpAllTables(await database);
    await _writeSafetySnapshot(snapshot);
    final path = join(await getDatabasesPath(), DbConstants.dbName);
    await close();
    await deleteDatabase(path);
    await _getOrCreateKey();
    await _secureStorage.write(key: _kEncEnabledFlag, value: 'true');
    try {
      final enc = await database; // reopens encrypted via _password()
      await _restoreAllTables(enc, snapshot);
      if (!_sameCounts(snapshot, await _dumpAllTables(enc))) {
        throw Exception('Row-count verification failed after encryption');
      }
    } catch (e) {
      // Roll back to plaintext — no data loss.
      await _secureStorage.write(key: _kEncEnabledFlag, value: 'false');
      await close();
      await deleteDatabase(path);
      await _restoreAllTables(await database, snapshot);
      rethrow;
    }
    // Success: don't leave a plaintext copy of the data next to the
    // freshly encrypted database.
    await _deleteSafetySnapshot();
  }

  /// Reverses [enableEncryption], returning the database to plaintext with the
  /// same verify-and-rollback safety.
  Future<void> disableEncryption() async {
    if (testFactory != null || dbNameOverride != null) {
      throw Exception('Encryption is not available in test mode');
    }
    if (!await isEncryptionEnabled()) return;
    final snapshot = await _dumpAllTables(await database);
    await _writeSafetySnapshot(snapshot);
    final path = join(await getDatabasesPath(), DbConstants.dbName);
    await close();
    await deleteDatabase(path);
    await _secureStorage.write(key: _kEncEnabledFlag, value: 'false');
    try {
      final plain = await database; // reopens plaintext
      await _restoreAllTables(plain, snapshot);
      if (!_sameCounts(snapshot, await _dumpAllTables(plain))) {
        throw Exception('Row-count verification failed after decryption');
      }
    } catch (e) {
      await _secureStorage.write(key: _kEncEnabledFlag, value: 'true');
      await close();
      await deleteDatabase(path);
      await _restoreAllTables(await database, snapshot);
      rethrow;
    }
    await _deleteSafetySnapshot();
  }
}
