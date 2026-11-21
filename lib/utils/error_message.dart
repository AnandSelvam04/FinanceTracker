import 'dart:io';

import 'app_logger.dart';

/// What a failed action tells the user: [action] in plain words ("Couldn't
/// save the transaction"), with a hint when the cause is one they can do
/// something about. The exception itself (often "Exception: Failed to insert
/// expense: DatabaseException(...)") goes to the log, not on screen.
String friendlyError(String action, Object error, [StackTrace? stackTrace]) {
  AppLogger.error(action, error, stackTrace);
  final hint = _hint(error);
  return hint == null ? '$action. Please try again.' : '$action. $hint';
}

String? _hint(Object error) {
  if (error is FileSystemException) {
    final code = error.osError?.errorCode;
    // ENOSPC: the phone's storage is full.
    if (code == 28) return 'The phone is out of storage space.';
    // EACCES / EPERM.
    if (code == 13 || code == 1) {
      return 'The app was not allowed to read or write that file.';
    }
    return 'A file could not be read or written.';
  }
  if (error is SocketException || error is HttpException) {
    return 'Check your internet connection and try again.';
  }
  if (error is FormatException) {
    return 'The file is not in a format the app can read.';
  }
  return null;
}
