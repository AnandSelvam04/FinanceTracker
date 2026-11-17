import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// A local path for a file the user picked, or null when they cancelled.
///
/// Since file_picker 12, Android can hand back a `content://` uri with no
/// path, and the restore and CSV import both read a [File]. Such a file is
/// copied into the app's temporary folder first. With [maxBytes], the copy
/// stops one byte past it, so the caller's own size check still trips
/// without the whole of a huge file being copied.
Future<String?> pickLocalFile({
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  int? maxBytes,
}) async {
  final picked = await FilePicker.pickFile(
      type: type, allowedExtensions: allowedExtensions);
  if (picked == null) return null;
  return picked.path ?? await _copyToTemp(picked, maxBytes);
}

Future<String> _copyToTemp(PlatformFile picked, int? maxBytes) async {
  final dir = await getTemporaryDirectory();
  final name = picked.name.replaceAll(RegExp(r'[/\\]'), '_');
  final copy = File('${dir.path}/picked_$name');
  final sink = copy.openWrite();
  var written = 0;
  try {
    await for (final chunk in picked.readAsByteStream()) {
      if (maxBytes != null && written + chunk.length > maxBytes) {
        sink.add(chunk.sublist(0, maxBytes + 1 - written));
        break;
      }
      sink.add(chunk);
      written += chunk.length;
    }
  } finally {
    await sink.close();
  }
  return copy.path;
}
