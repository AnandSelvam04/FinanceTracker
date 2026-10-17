import 'package:finance_tracker/services/db_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The dashboard fires several loads in the same frame on a cold start; they
/// must share one database open rather than each opening their own.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DBService.testFactory = databaseFactoryFfi;
  DBService.dbNameOverride = 'db_open_test.db';

  tearDown(() => DBService().close());

  test('concurrent first accesses share one open', () async {
    await DBService().close();
    final opens = await Future.wait(
        [DBService().database, DBService().database, DBService().database]);
    expect(identical(opens[0], opens[1]), isTrue);
    expect(identical(opens[1], opens[2]), isTrue);
  });

  test('close lets the next access reopen', () async {
    final first = await DBService().database;
    await DBService().close();
    final second = await DBService().database;
    expect(identical(first, second), isFalse);
    expect(second.isOpen, isTrue);
  });
}
