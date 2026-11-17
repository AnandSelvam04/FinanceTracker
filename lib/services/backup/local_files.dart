/// Where the backup and export files live on the phone, and how they are
/// written.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The app's documents folder, which holds the backups and exports.
Future<String> documentsPath() async =>
    (await getApplicationDocumentsDirectory()).path;

/// Writes [content] to [file] without ever leaving it half-written: the
/// data goes to a temporary file beside it, which is then renamed over the
/// target. A crash or a full disk mid-write used to truncate the only
/// backup on the phone; now the previous one survives intact.
Future<void> writeAtomically(File file, String content) async {
  final temp = File('${file.path}.tmp');
  try {
    await temp.writeAsString(content, flush: true);
    await temp.rename(file.path);
  } catch (_) {
    try {
      if (await temp.exists()) await temp.delete();
    } catch (_) {}
    rethrow;
  }
}
