import 'package:finance_tracker/services/auto_drive_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A scripted stand-in for Drive, recording what the policy asked it to do.
class _FakeDrive {
  DateTime? lastBackup;
  bool encrypted = false;
  String? passphrase;
  bool signedIn = true;
  bool remoteNewer = false;
  Object? remoteCheckError;
  final uploads = <String?>[];

  AutoDriveBackup policy(DateTime now) => AutoDriveBackup(
        lastDriveBackup: () async => lastBackup,
        isEncrypted: () async => encrypted,
        readPassphrase: () async => passphrase,
        isSignedIn: () async => signedIn,
        remoteIsNewer: () async {
          final error = remoteCheckError;
          if (error != null) throw error;
          return remoteNewer;
        },
        upload: (p) async => uploads.add(p),
        clock: () => now,
      );
}

void main() {
  final now = DateTime(2026, 11, 9, 9);
  late _FakeDrive drive;

  setUp(() {
    SharedPreferences.setMockInitialValues({AutoDriveBackup.kEnabled: true});
    drive = _FakeDrive();
  });

  test('does nothing while switched off', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await drive.policy(now).run(), AutoDriveStatus.off);
    expect(drive.uploads, isEmpty);
  });

  test('uploads when due, and records it', () async {
    drive.lastBackup = now.subtract(const Duration(days: 2));
    expect(await drive.policy(now).run(), AutoDriveStatus.done);
    expect(drive.uploads, [null]);
    expect(await AutoDriveBackup.lastStatus(), AutoDriveStatus.done);
  });

  test('waits a day after the last Drive backup', () async {
    drive.lastBackup = now.subtract(const Duration(hours: 20));
    expect(await drive.policy(now).run(), AutoDriveStatus.notDue);
    expect(drive.uploads, isEmpty);
  });

  test('seals with the stored passphrase', () async {
    drive
      ..encrypted = true
      ..passphrase = 'correct horse battery';
    expect(await drive.policy(now).run(), AutoDriveStatus.done);
    expect(drive.uploads, ['correct horse battery']);
  });

  test('never uploads in plaintext while the database is encrypted',
      () async {
    drive.encrypted = true;
    expect(await drive.policy(now).run(), AutoDriveStatus.needsPassphrase);
    expect(drive.uploads, isEmpty);
  });

  test('leaves a newer copy from another phone alone', () async {
    drive.remoteNewer = true;
    expect(await drive.policy(now).run(), AutoDriveStatus.remoteNewer);
    expect(drive.uploads, isEmpty);
  });

  test('skips when it cannot tell whether Drive holds a newer copy',
      () async {
    drive.remoteCheckError = Exception('offline');
    expect(await drive.policy(now).run(), AutoDriveStatus.failed);
    expect(drive.uploads, isEmpty);
  });

  test('never prompts: no signed-in account means no backup', () async {
    drive.signedIn = false;
    expect(await drive.policy(now).run(), AutoDriveStatus.notSignedIn);
    expect(drive.uploads, isEmpty);
  });

  test('after a try that did not upload, waits before trying again',
      () async {
    drive.remoteCheckError = Exception('offline');
    await drive.policy(now).run();
    drive.remoteCheckError = null;

    final soon = now.add(const Duration(hours: 1));
    expect(await drive.policy(soon).run(), AutoDriveStatus.notDue);
    expect(drive.uploads, isEmpty);

    final later = now.add(AutoDriveBackup.retryAfter);
    expect(await drive.policy(later).run(), AutoDriveStatus.done);
    expect(drive.uploads, hasLength(1));
  });

  test('force skips the timing checks', () async {
    drive.lastBackup = now.subtract(const Duration(minutes: 5));
    expect(await drive.policy(now).run(force: true), AutoDriveStatus.done);
    expect(drive.uploads, hasLength(1));
  });
}
