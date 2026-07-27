import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
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

  test('new envelopes record the current iteration count', () async {
    final envelope = await BackupCrypto.encryptString(secret, 'pw');
    expect(jsonDecode(envelope)['iterations'], 210000);
  });

  test('a backup written at the old 100k count still decrypts', () async {
    // Decryption used to derive with the hardcoded constant and ignore the
    // envelope's own `iterations`, so raising it would have made every
    // existing backup permanently unreadable. This is the regression guard.
    final envelope = await BackupCrypto.encryptString(secret, 'pw');
    final map = jsonDecode(envelope) as Map<String, dynamic>;
    expect(map['iterations'], isNot(100000));

    // Re-derive the same plaintext at 100,000 iterations, exactly as an older
    // build would have written it.
    final legacy = await _encryptAt(secret, 'pw', 100000);
    expect(jsonDecode(legacy)['iterations'], 100000);
    expect(await BackupCrypto.decryptString(legacy, 'pw'), secret);
  });

  test('an implausible iteration count is rejected, not attempted', () async {
    final envelope = await BackupCrypto.encryptString(secret, 'pw');
    final map = jsonDecode(envelope) as Map<String, dynamic>;
    map['iterations'] = 999999999;
    expect(BackupCrypto.decryptString(jsonEncode(map), 'pw'),
        throwsA(isA<FormatException>()));
  });

  test('an envelope with no iterations field is treated as legacy', () async {
    final legacy = await _encryptAt(secret, 'pw', 100000);
    final map = jsonDecode(legacy) as Map<String, dynamic>;
    map.remove('iterations');
    expect(await BackupCrypto.decryptString(jsonEncode(map), 'pw'), secret);
  });
}

/// Builds an envelope at an arbitrary iteration count, mimicking what an older
/// build of the app wrote.
Future<String> _encryptAt(
    String plaintext, String passphrase, int iterations) async {
  final rnd = Random.secure();
  final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
  final nonce = List<int>.generate(12, (_) => rnd.nextInt(256));
  final key = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  ).deriveKeyFromPassword(password: passphrase, nonce: salt);
  final box = await AesGcm.with256bits()
      .encrypt(utf8.encode(plaintext), secretKey: key, nonce: nonce);
  return jsonEncode({
    'magic': 'ft-enc-v1',
    'kdf': 'pbkdf2-hmac-sha256',
    'iterations': iterations,
    'salt': base64Encode(salt),
    'nonce': base64Encode(nonce),
    'ct': base64Encode(box.cipherText),
    'mac': base64Encode(box.mac.bytes),
  });
}
