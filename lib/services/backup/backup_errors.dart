/// The errors and results the backup code hands to the screens.
library;

/// Raised when a Google Drive operation can't proceed. Carries a
/// user-friendly [message]; the underlying Google Sign-In failures surface as
/// cryptic codes (e.g. `ApiException: 10`) that mean nothing to a user.
class DriveBackupException implements Exception {
  final String message;
  DriveBackupException(this.message);
  @override
  String toString() => message;
}

/// Raised when a backup is passphrase-encrypted and no passphrase (or the
/// wrong one) was given. The caller asks the user for it and tries again.
class PassphraseRequiredException implements Exception {
  /// True when a passphrase was given but didn't open the backup.
  final bool wrongPassphrase;
  PassphraseRequiredException({this.wrongPassphrase = false});
  @override
  String toString() => wrongPassphrase
      ? 'That passphrase did not open the backup.'
      : 'This backup is protected with a passphrase.';
}

/// Raised when a file offered for restore isn't a backup at all (wrong JSON
/// shape, a renamed CSV, a truncated download). Restoring clears the database
/// first, so this must be caught *before* anything is wiped.
class BackupFormatException implements Exception {
  final String message;
  BackupFormatException(this.message);
  @override
  String toString() => message;
}

/// Raised when a backup parses correctly but contains no rows in any table.
/// Applying it would silently wipe every transaction, so the caller must
/// confirm with the user and retry with `allowEmpty: true`.
class EmptyBackupException implements Exception {
  final String message;
  EmptyBackupException(this.message);
  @override
  String toString() => message;
}

/// The outcome of `BackupService.verifyLocalBackup`: whether the local backup
/// would actually restore, and how many rows it holds per table.
class BackupVerification {
  final bool ok;

  /// Row count per table when [ok]; empty otherwise.
  final Map<String, int> counts;

  /// A user-facing reason when not [ok]; null when it verified.
  final String? error;

  const BackupVerification._(this.ok, this.counts, this.error);

  factory BackupVerification.success(Map<String, int> counts) =>
      BackupVerification._(true, counts, null);

  factory BackupVerification.failure(String error) =>
      BackupVerification._(false, const {}, error);

  /// Total rows across every table.
  int get total => counts.values.fold(0, (a, b) => a + b);
}
