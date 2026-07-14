import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/services/backup_crypto.dart';

void main() {
  const secret = '{"version":4,"expenses":[{"amount":1250}]}';

  test('encrypt then decrypt round-trips the plaintext', () async {
    final envelope = await BackupCrypto.encryptString(secret, 'hunter2');
    expect(BackupCrypto.isEncrypted(envelope), isTrue);
    expect(envelope.contains(secret), isFalse); // not stored in the clear
    final restored = await BackupCrypto.decryptString(envelope, 'hunter2');
    expect(restored, secret);
  });

  test('a wrong passphrase cannot decrypt', () async {
    final envelope = await BackupCrypto.encryptString(secret, 'correct');
    expect(BackupCrypto.decryptString(envelope, 'wrong'), throwsA(anything));
  });

  test('isEncrypted is false for plain JSON and non-JSON', () {
    expect(BackupCrypto.isEncrypted('{"version":4}'), isFalse);
    expect(BackupCrypto.isEncrypted('not json at all'), isFalse);
  });

  test('each encryption uses a fresh salt/nonce', () async {
    final a = await BackupCrypto.encryptString(secret, 'pw');
    final b = await BackupCrypto.encryptString(secret, 'pw');
    expect(a, isNot(b));
  });
}
