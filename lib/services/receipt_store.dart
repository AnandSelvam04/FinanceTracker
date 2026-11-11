import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db_service.dart';

/// Receipt photos kept with transactions, in a `receipts` folder inside the
/// app's private documents directory. A transaction stores the photo's path
/// relative to that directory, so it survives the app's data folder moving.
///
/// Photos stay on the device: they are not uploaded anywhere, and JSON / Drive
/// backups carry the path but not the image.
class ReceiptStore {
  ReceiptStore._();

  /// Stands in for the documents directory in tests.
  static Directory? baseOverride;

  static Future<Directory> _base() async =>
      baseOverride ?? await getApplicationDocumentsDirectory();

  static const _folder = 'receipts';

  /// Copies the photo at [sourcePath] into the store and returns the path to
  /// save on the transaction.
  static Future<String> save(String sourcePath) async {
    final base = await _base();
    final dir = Directory(p.join(base.path, _folder));
    await dir.create(recursive: true);
    final ext =
        p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    final name = 'r${DateTime.now().microsecondsSinceEpoch}$ext';
    await File(sourcePath).copy(p.join(dir.path, name));
    // Stored with `/` on every platform (posix), so a saved path reads the
    // same on any host and matches the key [prune] builds.
    return p.posix.join(_folder, name);
  }

  /// The file for a stored [attachment] path.
  static Future<File> fileFor(String attachment) async =>
      File(p.join((await _base()).path, attachment));

  /// Detaches photos that are not on this device from their transactions,
  /// and returns how many transactions that touched.
  ///
  /// Backups carry a photo's path but not the image, so a backup restored on
  /// another phone (or after a reinstall) brings back transactions marked as
  /// having a receipt that opens to nothing. Run after a restore.
  static Future<int> forgetMissing() async {
    final base = await _base();
    final missing = <String>[];
    for (final a in await DBService().referencedAttachments()) {
      if (!await File(p.join(base.path, a)).exists()) missing.add(a);
    }
    if (missing.isEmpty) return 0;
    return DBService().clearAttachments(missing);
  }

  /// Deletes stored photos no transaction refers to any more — left behind
  /// by deleted or edited transactions. Run at launch rather than on delete,
  /// so undoing a delete keeps its photo.
  static Future<int> prune() async {
    final dir = Directory(p.join((await _base()).path, _folder));
    if (!await dir.exists()) return 0;
    final keep = await DBService().referencedAttachments();
    var removed = 0;
    await for (final f in dir.list()) {
      if (f is! File) continue;
      final rel = p.posix.join(_folder, p.basename(f.path));
      if (keep.contains(rel)) continue;
      await f.delete();
      removed++;
    }
    return removed;
  }
}
