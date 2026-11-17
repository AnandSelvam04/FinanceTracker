/// The one keystore-backed store the app uses: the database encryption key
/// and the automatic Drive backup's passphrase.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Every caller must use this instance: the options decide how Android
/// reads what was saved, so two differently configured stores could disagree
/// about the same data.
///
/// - `resetOnError: false` — flutter_secure_storage 10 turns reset-on-error
///   on by default, which **erases everything stored** when a read fails.
///   Here that would delete the database key and lock the user out of an
///   encrypted database for good; failing the read is recoverable, erasing is
///   not.
/// - `migrateWithBackup: true` — version 10 moves data saved by version 9
///   (RSA PKCS#1 + AES-CBC) to the current ciphers on first access. With
///   this, a copy is kept until the move completes, so a crash mid-way
///   cannot lose the key.
///
/// Do not jump to flutter_secure_storage 11 until every install has run a
/// build on 10 once: 11 can no longer read data in the version 9 format.
const appSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(resetOnError: false, migrateWithBackup: true),
);
